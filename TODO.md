# ex_gocd Feature Parity Implementation Plan

*Auto-generated and continuously updated. See `docs/comprehensive_parity_plan.md` for full context.*
*Last updated: 2026-06-21*

## ✅ Completed — Feature Parity

### P0: User-Visible Gaps
- [x] **Test report generation** — JUnit XML → HTML via xmerl + HTML builder
- [x] **Console log auto-scroll** — JS ConsoleScroller hook
- [x] **Artifact tree browser** — recursive expand/collapse directories
- [x] **Honest job state** — no more fake "Completed/Passed" mock
- [x] **Tests + Materials tabs** in job details page

### P1: Artifact Integrity
- [x] **MD5 checksums for artifacts** — agent uploads checksums, server stores to `cruise-output/md5.checksum` (functional, needs tests)
- [x] **Agent resource/environment matching** — Agent schema: `resources`, `environments`. Job schema: `resources`. Scheduler `find_matching_job/2` matches case-insensitively.

### P2: REST API Parity
- [x] **Pipeline instance API** — `GET /api/pipelines/:name/history`, `GET /api/pipelines/:name/:counter`
- [x] **Job instance API** — `GET /api/jobs/.../.../.../.../...`, `GET /api/jobs/.../.../.../history`
- [x] **Stage instance API** — `GET /api/stages/.../.../.../...`, `GET /api/stages/.../.../history`, `POST /api/stages/.../.../.../cancel`
- [x] **Users CRUD API** — `GET/POST/PATCH/DELETE /api/users/...`
- [x] **Stage cancel** — `Pipelines.cancel_stage/3` marks jobs Cancelled, broadcasts update

### Fixes
- [x] charlist `~c""` deprecation (Elixir 1.20)
- [x] xmerl tuple patterns (10-12 element tuples)
- [x] vsm_tracer unused variable warning
- [x] Credo: `with→case`, poller dedup

## 🔴 P1: Remaining

- [ ] **Fetch artifact task** — agent-side fetch from server + checksum verify
- [ ] **Console activity monitor** — cancel hung builds on inactivity timeout

## 🟡 P2: Remaining

- [ ] **Pipeline config admin CRUD API** — `GET/POST/PUT/DELETE /api/admin/pipelines/:name`
- [ ] **Template admin CRUD API** — `GET/POST/PUT/DELETE /api/admin/templates/:name`
- [ ] **Cycle detection** — verify `CycleDetector` exists and is wired
- [ ] **Dashboard REST API** — `GET /api/dashboard` JSON endpoint
- [ ] **Environments CRUD API** — schema exists, needs controller

## 🟢 P3: Advanced Features

- [ ] Full config repos engine (YAML/JSON parsing, merge)
- [ ] External auth (OAuth/LDAP)
- [ ] Notifications (email via Swoosh)
- [ ] Backups
- [ ] Maintenance mode

## 🔵 P4: Analytics (from gocd-analytics-plugin)

- [ ] Agent state transitions table
- [ ] Agent utilization snapshots
- [ ] Pipeline workflow tracking
- [ ] 11 analytics queries (pipeline build time, agent utilization, VSM trends, etc.)
- [ ] Analytics API + chart UI

---

## Quality Baseline (last verified: 2026-06-21)

| Check | Status |
|-------|--------|
| `mix compile --warnings-as-errors` | ✅ Pass |
| `mix sobelow` | ✅ 0 findings |
| `mix credo` | ✅ No suggestions |
| `mix test` | ✅ 430 passed (0 flaky) |
| `go vet ./...` | ✅ No issues |
| `go test ./...` | ✅ All passing |
| `golangci-lint run` | ✅ 0 issues |
