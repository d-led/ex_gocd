# ex_gocd — Status & Remaining Work

> **Single source of truth**: `docs/comprehensive_parity_plan.md`
> Superseded: `docs/parity_roadmap_plan.md`, `docs/vsm_parity_plan.md`, `docs/auth_and_env_plan.md`, `docs/external-ci-pipeline-sync-plan.md`

*Last verified: 2026-06-30*

---

## Quick Status

| Area | Status |
|------|--------|
| Core scheduling (trigger, fan-in, timers, manual gates, lock behaviors) | ✅ |
| REST API (20 controllers, 83 actions) | ✅ |
| LiveView pages (19 modules) | ✅ |
| Plugin architecture (5 behaviours, Registry, AgentSelector wired) | ✅ |
| Clustering (libcluster + Horde, 10 distributed singletons) | ✅ |
| Elastic agent scheduler (k8s pod lifecycle) | ✅ |
| PipelineGrouper integration (dashboard plugin grouping) | ✅ |
| Go agent (`agent/`) | ✅ |

## Quality Baseline

| Check | Status |
|-------|--------|
| `mix compile --warnings-as-errors` | ✅ |
| `mix sobelow` | ✅ 0 findings |
| `mix credo` | ✅ No issues |
| `mix test` | ✅ 886 passed |
| `go vet ./...` | ✅ |
| `go test ./...` | ✅ |
| `golangci-lint run` | ✅ 0 issues |
| Cypress E2E | ✅ 15 specs, 108 tests |

## Remaining Work

| Priority | Item | Effort |
|----------|------|--------|
| 🟡 P2 | Enhanced compare dialog — any-two-instance pickers, side-by-side diff | M |
| 🟡 P2 | Gantt chart — dependency arrows between pipeline runs | M |
| 🟡 P2 | Embedded pipeline/stage stats in detail pages | ✅ Done (2026-06-30) |
| 🔴 P2 | Full config repos engine (PaC) — YAML/JSON parsing, git polling, merge | XL |
| 🔴 P2 | External auth plugin (Ueberauth: LDAP/OAuth/GitHub) | L |

