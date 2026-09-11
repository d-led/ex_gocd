#!/usr/bin/env python3
"""Logging reverse proxy for GoCD agent remoting traffic.

Purpose
-------
The GoCD agent<->server protocol is not documented as a wire spec. To build a
drop-in replacement agent (or server) we need byte-exact evidence of what the
official Java agent sends and what the official GoCD server answers.

This proxy sits between one official Java agent and a real GoCD server and
records every HTTP exchange as JSON Lines, so the protocol can be asserted in
tests instead of guessed from Java sources.

Usage
-----
    # upstream = the real GoCD server
    ./capture_remoting_proxy.py --listen 9999 --upstream http://localhost:8153 --out /tmp/remoting.jsonl

    # point an official agent at the proxy
    docker run --rm --add-host=host.docker.internal:host-gateway \
        -e GO_SERVER_URL=http://host.docker.internal:9999/go \
        -e AGENT_AUTO_REGISTER_KEY=123456789abcdef \
        gocd-official-goagent_1

Recorded shape (one JSON object per line)
-----------------------------------------
    {"n": 1, "method": "POST", "path": "/go/remoting/api/agent/ping",
     "request_headers": {...}, "request_body": "...",
     "status": 200, "response_headers": {...}, "response_body": "..."}

The response body is returned to the agent unchanged.
"""

from __future__ import annotations

import argparse
import base64
import gzip
import json
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

# Headers that must not be forwarded verbatim (hop-by-hop / recomputed).
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}

# The GoCD server gzips JSON responses whenever the client advertises support
# (the real Java agent does, via Apache HttpClient). Gzipped payloads are
# useless in a capture file, so the proxy asks upstream for identity encoding.
# The body bytes are otherwise identical to what a real agent receives.
STRIPPED_REQUEST_HEADERS = {"accept-encoding"}

RECORDED_HEADERS = {
    "content-type",
    "content-encoding",
    "content-length",
    "accept",
    "authorization",
    "x-agent-guid",
    "x-go-artifact-size",
    "content-md5",
    "agent-content-md5",
}


def _body_fields(body: bytes, content_encoding: str | None) -> dict[str, str]:
    """Encode a body for the capture file.

    GoCD returns some payloads (agent token, cookie) as opaque bytes, so the raw
    bytes are always preserved as base64. A decoded text rendering is added when
    the bytes are valid UTF-8, to keep the file greppable.
    """
    if content_encoding == "gzip":
        try:
            body = gzip.decompress(body)
        except OSError:
            pass

    fields = {"body_b64": base64.b64encode(body).decode("ascii")}
    try:
        fields["body_text"] = body.decode("utf-8")
    except UnicodeDecodeError:
        pass
    return fields


class Recorder:
    """Append-only, thread-safe JSONL record writer."""

    def __init__(self, out_path: str) -> None:
        self._out_path = out_path
        self._lock = threading.Lock()
        self._count = 0
        # Truncate on start so each capture run is self-contained.
        with open(self._out_path, "w", encoding="utf-8"):
            pass

    def record(self, entry: dict[str, Any]) -> None:
        with self._lock:
            self._count += 1
            entry["n"] = self._count
            with open(self._out_path, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry) + "\n")


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    recorder: Recorder
    upstream: str
    verbose: bool

    def do_GET(self) -> None:
        self._proxy("GET")

    def do_HEAD(self) -> None:
        # The agent launcher probes for updated agent jars with HEAD requests.
        self._proxy("HEAD")

    def do_OPTIONS(self) -> None:
        self._proxy("OPTIONS")

    def do_POST(self) -> None:
        self._proxy("POST")

    def do_PUT(self) -> None:
        self._proxy("PUT")

    def do_DELETE(self) -> None:
        self._proxy("DELETE")

    def log_message(self, fmt: str, *args: Any) -> None:
        # Default handler logs to stderr on every request; keep it quiet unless asked.
        if self.verbose:
            sys.stderr.write("proxy: " + (fmt % args) + "\n")

    def _proxy(self, method: str, redirects_left: int = 3) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""

        forward_headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP
            and key.lower() not in STRIPPED_REQUEST_HEADERS
        }

        upstream_url = self.upstream.rstrip("/") + self.path
        request = urllib.request.Request(
            upstream_url, data=body or None, headers=forward_headers, method=method
        )

        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                status = response.status
                response_body = response.read()
                response_headers = dict(response.headers.items())
        except urllib.error.HTTPError as error:
            status = error.code
            response_body = error.read()
            response_headers = dict(error.headers.items())
        except urllib.error.URLError as error:
            self._fail_upstream(error)
            return
        except ConnectionResetError as error:
            # The agent aborted the connection (restart, timeout). There is
            # nothing to forward, and the client is already gone.
            self.recorder.record(
                {
                    "method": method,
                    "path": self.path,
                    "status": None,
                    "error": f"client disconnected: {error}",
                }
            )
            return

        # The GoCD server redirects /go -> /go/ and similar. Follow manually so the
        # exchange is still recorded under the original path.
        if status in (301, 302, 303, 307, 308) and redirects_left > 0:
            location = response_headers.get("Location") or response_headers.get("location")
            if location:
                self._follow_redirect(method, location, request, redirects_left)
                return

        self._write_response(status, response_headers, response_body)
        self.recorder.record(
            {
                "method": method,
                "path": self.path,
                "request_headers": _filtered(self.headers.items()),
                "status": status,
                "response_headers": _filtered(response_headers.items()),
                **_body_fields(body, self.headers.get("Content-Encoding")),
                **{
                    "res_" + key: value
                    for key, value in _body_fields(
                        response_body, _header(response_headers, "content-encoding")
                    ).items()
                },
            }
        )

    def _follow_redirect(
        self, method: str, location: str, original: urllib.request.Request, redirects_left: int
    ) -> None:
        if location.startswith("/"):
            target = self.upstream.rstrip("/") + location
        else:
            target = location
        redirected = urllib.request.Request(
            target, data=original.data, headers=dict(original.headers), method=method
        )
        try:
            with urllib.request.urlopen(redirected, timeout=120) as response:
                status = response.status
                response_body = response.read()
                response_headers = dict(response.headers.items())
        except urllib.error.HTTPError as error:
            status = error.code
            response_body = error.read()
            response_headers = dict(error.headers.items())
        except urllib.error.URLError as error:
            self._fail_upstream(error)
            return

        self._write_response(status, response_headers, response_body)
        self.recorder.record(
            {
                "method": method,
                "path": self.path,
                "redirected_to": location,
                "request_headers": _filtered(original.headers.items()),
                "status": status,
                "response_headers": _filtered(response_headers.items()),
                **_body_fields(original.data or b"", None),
                **{
                    "res_" + key: value
                    for key, value in _body_fields(
                        response_body, _header(response_headers, "content-encoding")
                    ).items()
                },
            }
        )

    def _fail_upstream(self, error: urllib.error.URLError) -> None:
        payload = json.dumps({"error": f"upstream unreachable: {error}"}).encode()
        self._write_response(502, {"Content-Type": "application/json"}, payload)
        self.recorder.record(
            {
                "method": self.command,
                "path": self.path,
                "status": 502,
                "error": str(error),
            }
        )

    def _write_response(
        self, status: int, headers: dict[str, str], body: bytes
    ) -> None:
        self.send_response(status)
        for key, value in headers.items():
            if key.lower() in HOP_BY_HOP:
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        # A HEAD response carries metadata only; writing the entity would desync
        # the connection.
        if self.command != "HEAD":
            self.wfile.write(body)


def _filtered(headers: Any) -> dict[str, str]:
    """Keep only the headers that carry protocol meaning."""
    return {
        key: value
        for key, value in headers
        if key.lower() in RECORDED_HEADERS
    }


def _header(headers: dict[str, str], name: str) -> str | None:
    """Case-insensitive header lookup."""
    wanted = name.lower()
    for key, value in headers.items():
        if key.lower() == wanted:
            return value
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen", type=int, default=9999, help="port to listen on")
    parser.add_argument(
        "--upstream", required=True, help="base URL of the real GoCD server"
    )
    parser.add_argument("--out", required=True, help="JSONL capture file to write")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    ProxyHandler.recorder = Recorder(args.out)
    ProxyHandler.upstream = args.upstream
    ProxyHandler.verbose = args.verbose

    server = ThreadingHTTPServer(("0.0.0.0", args.listen), ProxyHandler)
    print(f"capturing {args.upstream} -> {args.out} on port {args.listen}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
