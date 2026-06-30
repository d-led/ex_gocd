# GoCD Parity Implementation Roadmap

> **⚠️ SUPERSEDED** — See `docs/comprehensive_parity_plan.md` for the current state.
> This file is kept for historical reference only. Phases 1-10 are all complete.

✅ = Done, 🟡 = In progress, 🔴 = Not started

---

## ✅ Phase 1-8: COMPLETE — see commit history for details

All core scheduling, fan-in, timers, manual gates, API parity, webhooks, SCMM polling, pipeline-as-code, RBAC, and lock behaviors are implemented.

---

## 🔴 Phase 9: Elastic Agent Scheduler (k8s + docker)

When a job fires with `run_on_all_agents: true` and no matching agent exists, the server must spin up an elastic agent pod.

### Architecture (mirrors GoCD's kubernetes-elastic-agents plugin)

```
Server receives job with resources=[docker] and run_on_all_agents=true
  → No matching agent found
  → ExGoCD.ElasticAgentScheduler creates a pod via ExGoCD.K8s.create_pod()
  → Pod runs GoCD agent binary with GO_SERVER_URL env var
  → Agent auto-registers with server
  → Agent picks up the job
  → On job completion + idle timeout → pod deleted
```

### Tasks
- [ ] `ElasticAgentScheduler` GenServer: periodic ping to check for pending jobs without agents
- [ ] Match elastic agent profiles to pending jobs (image, resources, cluster profile)
- [ ] Create pod via `ExGoCD.K8s.create_pod()` (k8s) or docker API (docker)
- [ ] Pod lifecycle: create → register → execute → idle timeout → delete
- [ ] Idle cleanup on server ping (mirrors GoCD's `ServerPingRequestExecutor`)
- [ ] Pre-seeded k3s cluster profile in dev environment
- [ ] Agent smoke test running on all agent types: regular, docker, docker-elastic, k8s-elastic
- [ ] Integration test: trigger pipeline → pod created → agent registers → job completes → pod deleted

---

## 🔴 Phase 10: K8s Agent Config UI

Users need a UI to configure cluster profiles and elastic agent profiles — no curl.

### Tasks
- [ ] Admin tab: "Elastic Agent Configurations" with cluster profile + elastic agent profile forms
- [ ] Copy-paste kubeconfig into secret store (cluster profile)
- [ ] Elastic agent profile: pick image, resources, cluster profile
- [ ] Test: pre-seed k3s config, trigger agent-smoke-test, verify k8s agent runs

---

## 🔴 Phase 11: Enhanced Compare Dialog

GoCD allows comparing ANY two pipeline instances, not just consecutive ones.

### Tasks
- [ ] Dropdown pickers for from/to pipeline counter selection
- [ ] Side-by-side diff: material revisions, config changes, artifact changes
- [ ] URL format: `/compare/:pipeline/:from_counter/with/:to_counter`

---

## 🔴 Phase 12: Gantt Chart View

Timeline view of pipeline runs with dependency arrows.

Candidate: `phoenix_live_gantt` v0.4.0 — dependency arrows, sub-projects, click-to-detail popovers.

---

## 🔴 Phase 13: Embedded Pipeline/Stage Stats

Stats charts in pipeline and stage detail pages (not just analytics page).

---

## 🟡 Phase 14: Quality & Testing

### Cypress
- [ ] Fix VSM flake (1/27 test fails)
- [ ] Fix admin page login session persistence (tests need auth)

### GoCD Scheduler Test Parity
- [ ] Implement GoCD's scheduler test cases from `gocd/domain/src/test/`
- [ ] runOnAllAgents: all matching agents including LostContact/Missing
- [ ] runInstanceCount: N parallel instances
- [ ] Fan-in resolution edge cases
- [ ] Timer trigger edge cases

### k8s Tests
- [ ] Fix DynamicHTTPProvider mock integration (4 tests failing)
- [ ] Add integration test with real k3s cluster

---

## 🟡 Phase 15: PubSub Live Updates

- [x] `ExGoCD.PubSub` module with topic constants
- [x] `StageDetailsLive` subscribes to pipeline updates
- [ ] `DashboardLive` auto-refresh on pipeline state changes
- [ ] `PipelineActivityLive` auto-refresh
- [ ] `AgentsLive` auto-refresh on agent state changes
- [ ] `AdminLive` auto-refresh

