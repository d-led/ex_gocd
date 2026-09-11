# GoCD agent remoting protocol — captured fixtures

These files are **verbatim captures** of the traffic between an official GoCD
Java agent (`gocd/gocd-agent-alpine:v25.4.0`) and an official GoCD server
(`gocd/gocd-server:v25.4.0`). They are the executable specification for the
`/go/remoting/api/agent/*` endpoints implemented by
`ExGoCDWeb.AgentRemotingController` and by the Go agent.

Nothing here is hand-written. If the protocol is suspected to be wrong, re-run
the capture and diff — do not edit these by hand.

## Why captures instead of a spec

GoCD publishes no wire specification for the agent remoting API. The Java
sources describe the types, but the on-the-wire JSON is produced by Gson with
runtime type adapters, so the only trustworthy source is observed traffic.

## How these were captured

```bash
# 1. Official GoCD server + agents
docker compose -f gocd_docker_compose_example/static_config/docker-compose.yaml up -d

# 2. Logging reverse proxy in front of the server
python3 scripts/capture_remoting_proxy.py \
    --listen 9999 --upstream http://localhost:8153 --out /tmp/remoting.jsonl

# 3. One official Java agent pointed at the proxy
docker run -d --name capture-agent \
    --add-host=host.docker.internal:host-gateway \
    -e GO_SERVER_URL=http://host.docker.internal:9999/go \
    -e AGENT_AUTO_REGISTER_KEY=123456789abcdef \
    -e AGENT_AUTO_REGISTER_RESOURCES=capture \
    gocd-official-goagent_1

# 4. Trigger a pipeline (a minimal one requiring resource `capture`) so the
#    agent receives a real BuildWork instead of NoWork
curl -X POST -H "X-GoCD-Confirm: true" \
    "http://localhost:8153/go/api/pipelines/capture-protocol/schedule?materials=true"
```

## The contract as observed

All remoting calls are `POST` to `<base>/remoting/api/agent/<action>` with:

| Header | Value |
| --- | --- |
| `Accept` | `application/vnd.go.cd+json` |
| `Content-Type` | `application/json; charset=UTF-8` |
| `X-Agent-GUID` | the agent UUID |
| `Authorization` | the agent token from `GET /go/admin/agent/token?uuid=<uuid>` |

Responses are `application/vnd.go.cd.v1+json;charset=utf-8` and may be gzip
encoded when the client advertises `Accept-Encoding: gzip`.

| Action | Request `type` | Response |
| --- | --- | --- |
| `ping` | `PingRequest` | `"NONE"` — a *quoted* JSON string |
| `get_work` | `GetWorkRequest` | `{"type":"NoWork"}` or a `BuildWork` |
| `get_cookie` | `GetCookieRequest` | the raw cookie, unquoted |
| `is_ignored` | `IsIgnoredRequest` | `false` — the bare literal |
| `report_current_status` | `ReportCurrentStatusRequest` | empty body |
| `report_completing` | `ReportCompleteStatusRequest` | empty body |
| `report_completed` | `ReportCompleteStatusRequest` | empty body |

Console output is **not** a remoting action. The agent appends to
`PUT <base>/remoting/files/<pipeline>/<counter>/<stage>/<stageCounter>/<job>/cruise-output/console.log?attempt=1&buildId=<buildId>`
with `X-Go-Artifact-Size` set to the body length. Line prefixes are described in
`docs/gocd_console_log_format.md`.

## Files

| File | Meaning |
| --- | --- |
| `ping_request.json` | request body the Java agent sends |
| `ping_response.json` | `"NONE"` |
| `get_work_request.json` | request body for polling work |
| `no_work_response.json` | `{"type":"NoWork"}` |
| `build_work_response.json` | a real `BuildWork` with a `CommandBuilderWithArgList` task |
| `get_cookie_request.json` / `get_cookie_response.txt` | cookie retrieval |
| `is_ignored_request.json` / `is_ignored_response.txt` | ignore check |
| `report_*_request.json` | status/completion reports |
| `console_log_upload.txt` | a console-log append body |
