# GoCD Parity Implementation Roadmap

> **⚠️ SUPERSEDED** — See `docs/comprehensive_parity_plan.md` for the current state.
> This file is kept for historical reference only. All phases 1-15 are complete.

✅ = Done, 🟡 = In progress, 🔴 = Not started

---

## ✅ Phase 1-10: COMPLETE

All core scheduling, fan-in, timers, manual gates, API parity, webhooks, SCM polling, pipeline-as-code, RBAC, lock behaviors, elastic agent scheduler (k8s pod lifecycle), and K8s agent config UI are implemented. See `docs/comprehensive_parity_plan.md` for details.
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
