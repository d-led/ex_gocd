# PubSub and Real-Time Views

## Goal

When any user changes shared data (e.g. agents), **all** connected users see the update immediately without refreshing. This matches GoCD’s behavior and is implemented using Phoenix.PubSub.

## Pattern

1. **Context broadcasts on change**  
   The context that mutates data (e.g. `ExGoCD.Agents`) subscribes to a topic and **broadcasts** an event after each successful write:
   - `Phoenix.PubSub.subscribe(ExGoCD.PubSub, topic)` for subscribers
   - `Phoenix.PubSub.broadcast(ExGoCD.PubSub, topic, {event, payload})` after insert/update/delete

2. **LiveView subscribes in `mount`**  
   When the LiveView is **connected** (not on first render), subscribe to the topic:
   - `if connected?(socket), do: TheContext.subscribe()`

3. **LiveView handles broadcast with `handle_info`**  
   Implement `handle_info({event, payload}, socket)` and update assigns (e.g. reload list). The view re-renders and every user watching that page sees the new data.

## Current Implementation

### Agents

- **Topic**: `"agents:updates"`
- **Broadcasts**: `Agents` context broadcasts `:agent_registered`, `:agent_updated`, `:agent_enabled`, `:agent_disabled`, `:agent_deleted` after the corresponding operations.
- **Subscriber**: `AgentsLive` subscribes in `mount` when `connected?(socket)` and handles all five events by reloading the agents list.

So when user A enables an agent, user B’s agents table updates automatically.

### Agent Job Runs (list)

- **Topic**: `"agent_job_runs:{agent_uuid}"` (per-agent)
- **Broadcasts**: `AgentJobRuns` broadcasts `:run_created` and `:run_updated` (payload is `agent_uuid`) after `create_run/5` and `report_status/4`.
- **Subscriber**: `AgentJobHistoryLive` subscribes in `mount` when `connected?(socket)` via `AgentJobRuns.subscribe_job_runs(uuid)` and refetches the list on either event.

### Agent Job Run Console (single run)

- **Topic**: `"agent_job_run_console:{build_id}"`
- **Broadcasts**: `AgentJobRuns` broadcasts `{:console_append, chunk}` after `append_console/2` (when the agent POSTs console output); and `{:run_updated, run}` after `report_status/4` so the detail view can show Passed/Failed in real time.
- **Subscriber**: `AgentJobRunDetailLive` subscribes in `mount` when `connected?(socket)` via `AgentJobRuns.subscribe_console(build_id)` and handles `:console_append` (append chunk) and `:run_updated` (update run assign for result).

### Scheduler (queued jobs)

- **Topic**: `"scheduler:updates"`
- **Broadcasts**: `ExGoCD.Scheduler` broadcasts `{:pending_count, count}` when the job queue changes (after `schedule_job/1` or when an agent picks work in `try_assign_work/1`).
- **Subscriber**: `AgentsLive` subscribes when `connected?(socket)` via `ExGoCD.Scheduler.subscribe/0` and updates the "Queued jobs" count in real time.

### Dashboard (Pipelines)

- **No PubSub**: `DashboardLive` uses mock pipeline data and does not subscribe to any topic.

### Extending to Other Resources

For pipelines, job history, or other shared data:

1. Choose a topic (e.g. `"pipelines:updates"`).
2. In the context that mutates the data, call `Phoenix.PubSub.broadcast(ExGoCD.PubSub, topic, {event, payload})` after success.
3. In the LiveView that displays the data, subscribe in `mount` when `connected?(socket)` and add `handle_info/2` clauses to update assigns (e.g. reload list or merge the changed item).

### API-Triggered Changes

If a change is made via the **REST API** (e.g. `PUT /api/agents/:uuid/disable`), the same context functions (e.g. `Agents.disable_agent/1`) should be used. Those functions already broadcast, so LiveView subscribers will still receive the update. Do not duplicate broadcast logic in the API controller.

## References

- `lib/ex_gocd/agents.ex` – `subscribe/0`, `broadcast/2`, and where each event is broadcast
- `lib/ex_gocd_web/live/agents_live.ex` – subscription in `mount`, `handle_info` for each event
- `lib/ex_gocd/agent_job_runs.ex` – `subscribe_job_runs/1`, `subscribe_console/1`, and broadcasts on create/update/append_console
- `lib/ex_gocd_web/live/agent_job_history_live.ex` – subscribes to job runs list, refetches on `:run_created` / `:run_updated`
- `lib/ex_gocd/scheduler.ex` – `subscribe/0`, broadcasts `{:pending_count, count}` on queue change
- `lib/ex_gocd_web/live/agent_job_run_detail_live.ex` – subscribes to console topic when connected; handles `:console_append` and `:run_updated`
