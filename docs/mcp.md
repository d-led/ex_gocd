# The MCP server

`POST /mcp` speaks the Model Context Protocol over the Streamable HTTP
transport, so an assistant can ask about a running GoCD server — what is
configured, what ran, what is running now, why nothing is running, and what the
numbers say — and act on it.

It offers three things: **tools** (53 of them, below), **resources** (the
documents a person would attach: the dashboard, the configuration XML, the audit
trail, one pipeline's configuration) and **prompts** (the four workflows worth
following in order). Completions offer the values that exist while an argument is
typed — the pipeline names, mostly.

It is one endpoint, one JSON-RPC message in, one answer out. No sessions, no
server-sent events, no batches — every request is self-contained, which is what
lets a client treat it as a plain HTTP URL.

```bash
curl -s localhost:4000/mcp \
  -H 'content-type: application/json' \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "initialize",
       "params": {"protocolVersion": "2025-06-18"}}'
```

Point a client at the address the server prints (`4000` by default). VS Code
reads `.vscode/mcp.json`:

```json
{
  "servers": {
    "gocd": {
      "type": "http",
      "url": "http://localhost:4000/mcp"
    }
  }
}
```

## Where the answers come from

The server does not keep a copy of anything it talks about. Every tool calls the
same context the dashboard, the JSON API and the admin pages call, so an answer
from a tool and an answer from a page cannot differ.

| Question                                | Read from                                                       |
| --------------------------------------- | --------------------------------------------------------------- |
| What is this deployment?                | `ExGoCD.Pipelines`, `ExGoCD.Agents`, `ExGoCD.Scheduler`, `ExGoCD.ConfigVersion` |
| What is configured?                     | `ExGoCD.Pipelines` (`get_pipeline_by_name/1`, `list_materials/0`) |
| What ran, and how did it end?           | `ExGoCD.Pipelines` instances, stages and jobs; `ExGoCD.AgentJobRuns` for consoles |
| Why is work not moving?                 | `ExGoCD.Scheduler.get_queue_state/0`, `diagnose_pending_job/1`  |
| Who did what?                           | `ExGoCD.AuditLog.search/1`                                      |
| How are we trending?                    | `ExGoCD.Analytics`, `ExGoCD.Pipelines.ValueStreamMap`           |
| What is the whole configuration?        | `ExGoCD.ConfigXml.generate/0`, `ExGoCD.ConfigVersion`           |

## The tools

**The server** — `gocd_server_info` (version, counts, maintenance mode, disk),
`gocd_dashboard` (every pipeline's latest status), `gocd_queue` (what the
scheduler holds, and why a job with given resources is not picked up),
`gocd_audit_log`, `gocd_server_stats` (the `/api/stats` payload).

**Pipelines** — `gocd_list_pipelines` (configurations), `gocd_describe_pipeline`
(materials, stages, jobs, tasks, variables), `gocd_pipeline_status` (paused,
locked, schedulable, latest run), `gocd_pipeline_history`,
`gocd_pipeline_instance`, `gocd_pipeline_config_diff`,
`gocd_compare_pipeline_instances`.

**Acting on pipelines** — `gocd_trigger_pipeline`, `gocd_set_pipeline_paused`,
`gocd_unlock_pipeline`, `gocd_comment_on_pipeline`.

**Authoring pipelines** — `gocd_create_pipeline` takes `definition` for one
pipeline or `pipelines` for a graph, and writes either as one thing;
`gocd_update_pipeline` changes the pipeline's own settings (group, label
template, lock behaviour, paused, timer, parameters, variables),
`gocd_delete_pipeline` deletes it. Rewriting an existing pipeline's stages is
deliberately not offered: a stage's run history is keyed to the stage row, so
that is a migration rather than an edit.

### A graph, not a pipeline

GoCD's vocabulary for delivery is a graph, and the shapes are worth keeping the
moment a second pipeline exists:

- **fan-out** — one build, several deployments. Each deploy pipeline has the
  build as a `dependency` material and starts when it succeeds.
- **fan-in** — several upstreams, one pipeline that waits for all of them, so a
  production deploy cannot begin because UAT went green while staging was still
  running. Naming the same upstream stage on each dependency is what makes the
  wait mean something: the material watches *that* stage, not the end of the
  pipeline.
- **passing results** — the build job publishes `artifacts`; a deploy job has a
  `fetch` task that takes them, so what is deployed is the file that was built.
- **build once** — the four together: build the artifact once, promote that same
  artifact through every environment. It is why a deploy fetches rather than
  builds again.

`gocd_create_pipeline` writes a graph in two passes — every pipeline, then the
materials — so a dependency may name a pipeline declared later in the same call.
The answer names the edges and the shapes back (`fan-out from build to 2
pipelines`), with each pipeline's will-it-run verdict. `gocd_validate_pipeline`
checks the same graph without writing it, including the structural mistakes: a
cycle, a dependency nobody declares, and a fetch of an artifact nobody publishes.

Two GoCD limits worth knowing, both visible here. A material `include`/`exclude`
filter stops fan-in resolution working, so a filtered shared repository can leave
a fan-in target waiting forever. And `ignoreForScheduling` — a dependency that is
used but does not trigger — is not implemented in this server, so it is not
offered rather than accepted and ignored.

**Will it run?** — `gocd_audit_config`, `gocd_who_can_run`,
`gocd_validate_pipeline`. This is the question the old `will_it_go_cd` asked of a
`server.xml` and printed `<<<OOPS>>>` beside: a job nothing can take waits
forever, and the two reasons are ordinary — no agent holds a resource it asks
for, or the environments do not line up. Asked here, the answer comes from the
server's own configuration and cannot be stale; asked of a definition that has
not been created yet, it costs a sentence instead of a queue that never moves.
`gocd_create_pipeline` reports the same verdict for what it just built.

The environment half is the part people forget. GoCD's own rule
(`managing_environments.md`): an agent in an environment takes only that
environment's pipelines, and a pipeline in no environment goes only to agents in
no environment — so a new pipeline in a fleet whose agents all live inside
environments is taken by nobody until someone assigns it. The answer says that
rather than leaving it to be discovered.

**Reviewing the flow** — `gocd_review_delivery`. Given `definition`, `pipelines`,
or nothing at all (the configuration as it stands), it checks the **edges** and
only the edges — what depends on what, what is passed along, and whether the fleet
can run the shape that was drawn:

- **what passes between pipelines** — a deploy that depends on a build *and*
  checks out the same repository can rebuild what the build already built, so what
  it ships is not the artifact that was tested; a pipeline others depend on that
  publishes no artifacts gives them nothing to take; a `fetch` from a pipeline
  this one does not depend on takes whatever that pipeline produced last rather
  than the build this run is for.
- **the shape the fleet can run** — a stage of three jobs that only one agent can
  take is a queue however it is drawn, so the review counts how many agents can
  take those jobs at the same time and says when the stage runs in waves; a fleet
  of one agent makes every parallel stage serial, and that is said once rather
  than per stage.
- **where it runs** — a deploy that belongs to no environment is taken by the
  default pool, with nothing isolating it and no environment to be promoted
  through.

What a job *does* is left to its author, deliberately: the commands, how many
stages there are, whether a stage waits for a person, and where the configuration
is kept are decisions the server cannot judge from outside. The review reports
what it can assert about the flow and stops there — it never claims a build is
good, only that the edges are the ones the author drew.

**Stages** — `gocd_stage`, `gocd_stage_history`, `gocd_approve_stage`,
`gocd_cancel_stage`, `gocd_rerun_failed_jobs`.

**Jobs** — `gocd_job`, `gocd_job_console`, `gocd_job_history`,
`gocd_test_report` (the JUnit-style results a job published, failing cases named),
`gocd_schedule_job`.

**Agents** — `gocd_list_agents`, `gocd_agent`, `gocd_update_agent`,
`gocd_kill_agent_tasks`.

**Analytics** — `gocd_pipeline_analytics`, `gocd_agent_analytics`,
`gocd_value_stream_map`, `gocd_stage_trends` (one stage's last runs, oldest
first, with a median — the series the duration chart draws).

**Configuration** — `gocd_config_xml`, `gocd_config_history`,
`gocd_environments`, `gocd_materials`, `gocd_templates` (each template's stages
and the pipelines that use it), `gocd_pipeline_groups`.

**Administration** — `gocd_set_maintenance_mode` (stops or resumes scheduling;
asks for a confirmation before it stops anything), `gocd_create_backup`,
`gocd_backup_status`, `gocd_config_repos`, `gocd_refresh_config_repo`,
`gocd_list_users`. Each of these asks for the administrator check the web UI
makes, and reports a repository's configuration *keys* rather than its values,
because a git credential is one of them.

Every tool answers with two things: `text`, which a model reads, and
`structuredContent`, which is the same facts for a program. Every tool has an
`inputSchema` and honest annotations: the ones that only read say
`readOnlyHint`; the ones that write say that too; and the ones that can throw
work away — cancelling a stage, killing an agent's tasks, turning maintenance
mode on — say `destructiveHint` and refuse to act without `confirm: true`.

A tool that refuses its arguments answers with `isError: true` and a sentence
that says what to fix. That is the specification's way of saying "this call
failed, the message says how" rather than "the server is broken".

## Documents and workflows

Two things are not tools.

**Resources** are documents, addressed by URI, that a client lists and reads
whole: `gocd://dashboard`, `gocd://config.xml`, `gocd://audit/recent`, and — from
the template `gocd://pipelines/{name}` — one pipeline's configuration. Each one
is its tool's own structured answer (`gocd_dashboard`, `gocd_config_xml`,
`gocd_audit_log`, `gocd_describe_pipeline`), not a second implementation, so a
resource cannot drift into a slightly different truth from the tool beside it;
and a resource is read as the caller, with the caller's permissions.

```jsonc
{"jsonrpc": "2.0", "id": 1, "method": "resources/list"}
{"jsonrpc": "2.0", "id": 2, "method": "resources/read", "params": {"uri": "gocd://pipelines/build-app"}}
```

**Prompts** are the workflows a person asks for most often, written down once so
an assistant does not have to invent the order of the calls: `diagnose_pipeline`
(status → instance → the failed job → the end of its console → is it recurring),
`why_is_nothing_running` (nothing queued, nothing that can take it, or the
server refusing to schedule), `what_changed` (two runs compared, then the config
diff, then the audit log) and `fleet_health` (a period's pass rates, wait times
and agent utilization).

```jsonc
{"jsonrpc": "2.0", "id": 3, "method": "prompts/get",
 "params": {"name": "diagnose_pipeline", "arguments": {"pipeline": "build-app"}}}
```

**Completions** are the menu a client offers while an argument is being typed:
the `pipeline` argument of `diagnose_pipeline` and `what_changed`, the `name` of
the `gocd://pipelines/{name}` template, and the `days` of `fleet_health`. They
come from the pipelines that exist, filtered by what has been typed. A
completion is a convenience, not a permission: the value a client settles on is
checked again by the tool or resource it is used with.

## Authentication

Four credentials are accepted, in this order, because they are the ones the
server's other surfaces already accept:

| Caller                                                    | Credential                                   |
| --------------------------------------------------------- | -------------------------------------------- |
| a client with a GoCD access token                         | `Authorization: Bearer <token>`              |
| a client with a token and a username                      | `Authorization: Basic base64(user:token)`    |
| a browser, or a reader `oauth2-proxy` authenticated       | the session cookie                           |
| a client that supports OAuth discovery                    | none — it walks the round trip below         |
| nobody, on a server with no administrator configured      | the guest, who is an administrator in open mode |

There is no password form. Signing in to this server identifies a user; it does
not authenticate one against a secret, and no password is stored.

A credential that is *presented* and wrong is a `401`, never a silent fallback
to the guest — but a call that presents nothing is a guest call, exactly as the
JSON API treats it. Set `EX_GOCD_MCP_REQUIRE_AUTH=true` (or
`:mcp_require_auth` in config) to refuse those too, which is what a deployment
reachable from the internet wants.

### The authorization round trip

The server is its own OAuth 2.1 authorization server for MCP, so a client that
supports remote servers walks the flow by itself:

1. `POST /mcp` without a credential → **401** with
   `WWW-Authenticate: Bearer realm="gocd", resource_metadata="…/.well-known/oauth-protected-resource"`
   (only while credentials are required — otherwise the guest is answered);
2. the client reads `/.well-known/oauth-protected-resource` (RFC 9728) and
   `/.well-known/oauth-authorization-server` (RFC 8414), then **registers
   itself** at `POST /oauth/register` (public client, no secret);
3. the reader's browser opens `GET /oauth/authorize` — if they are not signed in
   they are sent to `/auth/login` and brought back — and sees one consent page:
   *allow this client to act as you?*;
4. approving redirects back with a code, and `POST /oauth/token` trades it
   (PKCE S256, code valid five minutes, single use) for an access token.

The access token **is** a GoCD personal access token:
`ExGoCD.Accounts.create_user_token/2` mints it and
`ExGoCD.Accounts.verify_access_token/1` checks it, so it is worth the same as a
token pasted from the access tokens page. It appears there as
`MCP client: <name>`, revoking it there ends the client's access, and disabling
the user stops the next call. Revocation is about the account and the token, not
about a session this server keeps.

An authorization request is validated *before* anything is redirected: an
unknown client, or a `redirect_uri` the client did not register, is answered
with a `400` in the browser rather than with a redirect carrying a code
somewhere else.

### What oauth2-proxy still has to do

oauth2-proxy is an OIDC *client*: it logs the reader in and sets
`X-Forwarded-User` / `X-Forwarded-Email`. `ExGoCDWeb.Plugs.AuthHeaderPlug`
turns those headers into a session, and `ExGoCD.Mcp.Identity` accepts that
session, so a reader already signed in to the UI does not mint a token to use
the MCP server.

Two things are the deployment's business:

- the proxy must **skip** `/mcp`, `/oauth/token`, `/oauth/register` and
  `/.well-known/…`, which are machine-to-machine paths and must not be answered
  with the proxy's own 302 to the identity provider. `/oauth/authorize` is
  **not** skipped: that is the browser step, and the proxy is what identifies
  the reader there;
- provisioning is off unless asked for: `EX_GOCD_AUTO_CREATE_USERS=true` creates
  an account on first sight of the header, and `EX_GOCD_ADMIN_USERS` (a
  comma-separated list) says who is an administrator. Trusting a forwarded
  header means the endpoint must not be reachable except through the proxy.

## Configuration

| Setting                            | Default | What it is                                                         |
| ---------------------------------- | ------- | ------------------------------------------------------------------ |
| `EX_GOCD_MCP_REQUIRE_AUTH`         | unset   | `true` refuses a call that presents no credential, with the challenge |
| `EX_GOCD_AUTO_CREATE_USERS`        | `false` | create an account for a username a reverse proxy forwards          |
| `EX_GOCD_ADMIN_USERS`              | unset   | who is an administrator among those forwarded usernames            |

## What it is not

No server-sent events and no sessions: `GET /mcp` and `DELETE /mcp` answer
`405`, and every request stands alone. No sampling and no roots — tools,
resources and prompts, and nothing behind them that is not the server already
has. No per-tool scopes: a token sees what its reader sees, and the write tools
check the same permissions the web UI checks.

`Origin`, when a client sends one, must name this host — the DNS-rebinding
defence the specification asks for — and `MCP-Protocol-Version`, when a client
sends one, must be a revision the server speaks
(`2025-06-18`, `2025-03-26`, `2024-11-05`).
