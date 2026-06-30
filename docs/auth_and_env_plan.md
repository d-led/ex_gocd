# Auth, Environments & Agent Job Types — Feature Parity Plan

> **⚠️ SUPERSEDED** — Auth, Environments, RBAC are complete. See `docs/comprehensive_parity_plan.md` for current state.

*2026-06-22. Kept for historical reference.*

---

## Part A: Current State — Audited

### Authentication
| Feature | Status | Notes |
|---------|--------|-------|
| Guest admin (open mode) | ✅ Fixed | DB had stale admin users; cleaned. `admin_configured?` → false → guest gets admin |
| Guest viewer (security mode) | ✅ | When admin exists, guest gets viewer role |
| AuthHeaderPlug (x-forwarded-user) | ✅ | Reverse proxy auth; auto-create when EX_GOCD_AUTO_CREATE_USERS=true |
| TokenAuthPlug (Bearer tokens) | ✅ | PAT-based auth for API |
| Personal Access Tokens | ✅ | CRUD API at /api/current_user/access_tokens |
| User CRUD | ✅ | API-only, no UI |
| Auto user creation | ✅ | `EX_GOCD_AUTO_CREATE_USERS=true` → AuthHeaderPlug creates users |
| Pre-seeded admin | ✅ | `EX_GOCD_ADMIN_USERS=admin@example.com` → gets admin role |
| OAuth2 proxy example | ✅ | `examples/oauth2-proxy/` — real oauth2-proxy image v7.15.3, htpasswd, docker-compose |

### Environments
| Feature | Status | Notes |
|---------|--------|-------|
| Environment schema | ✅ | `environments` table, joins for pipelines + agents |
| Environment CRUD API | ✅ | `/api/admin/environments` |
| Agent→environment assignment | ❌ | Schema exists but agent.environments not wired to scheduling |
| Pipeline→environment gating | ❌ | No env-based trigger restriction |
| Environment UI | ❌ | No LiveView page for environment management |
| Environment variables per env | ❌ | Not implemented |

### OAuth2 / Reverse Proxy Auth
| Feature | Status | Notes |
|---------|--------|-------|
| x-forwarded-user header | ✅ | AuthHeaderPlug reads it |
| Auto user creation | ❌ | Currently refused (ensure_user returns nil) |
| Pre-seeded admin | ❌ | No seeding; relies on first-user-admin |
| OAuth2 proxy (e.g. oauth2-proxy) | ❌ | No integration |

### Job Types / Agent Scheduling
| Feature | Status | Notes |
|---------|--------|-------|
| Run on all agents | ✅ | Scheduler creates one queue entry per matching agent; `schedule_test_job` uses it |
| Run multiple instance | ❌ | GoCD's RunMultipleInstance |
| schedule_test_job | ✅ | Runs on all enabled agents via `run_on_all_agents: true` |
| Resource matching | ✅ | `resources_match?` in scheduler |
| Environment matching | ⚠️ Partial | `envs_match?` exists but envs not populated on agents |

---

## Part B: Implementation Plan

### Phase 1: Fix Immediate Issues

- [x] **Guest admin**: Clean stale admin users from DB → `admin_configured?` returns false → guest gets admin role
- [ ] **Fix schedule_test_job**: Verify GenServer handle_call works; ensure test job runs on all enabled agents
- [ ] **Ensure tests don't pollute DB**: Make tests use sandbox properly or clean up after

### Phase 2: Run on All Agents (Job Type)

GoCD's `RunOnAllAgents` (JobType interface):
- Job configured with `run_on_all_agents: true`
- Scheduler creates one job instance per matching agent
- Job names: `jobname-runonall-{agent_uuid}`
- Each agent gets its own instance

Implementation:
1. Add `run_on_all_agents` boolean to Job schema
2. In scheduler, when a job with `run_on_all_agents` is triggered:
   - Query all enabled agents matching resources/environments
   - Create one JobInstance per agent
   - Name them `{job_name}-runonall-{short_uuid}`
3. UI: add checkbox to pipeline config wizard
4. Dedicated test pipeline view showing per-agent results

### Phase 3: Environments Deep Implementation

1. **Agent environment assignment**: When agent registers, if env specified, assign it
2. **Environment-based scheduling**: Only assign jobs to agents in matching environment
3. **Environment LiveView page**: CRUD UI for environments with pipeline/agent assignment
4. **Environment variables**: Per-environment env vars that override pipeline vars

### Phase 4: Auth / OAuth2 Strategy

**Principle**: Support reverse-proxy auth (oauth2-proxy, Authelia, etc.) with automatic user creation.

**Flow**:
1. `oauth2-proxy` (or similar) sits in front of ex_gocd
2. Proxy authenticates user, sets `X-Forwarded-User`, `X-Forwarded-Email`, `X-Forwarded-Roles` headers
3. `AuthHeaderPlug` reads headers
4. If user doesn't exist in DB: **auto-create with pre-configured role mapping**
5. Pre-seeded admin: via env var `EX_GOCD_ADMIN_USERS=admin@example.com`

**Safe auto-creation rules**:
- Only when `x-forwarded-user` header is present (not for direct access)
- Default role: `[]` (viewer) for new users
- Admin role: only if username matches `EX_GOCD_ADMIN_USERS` env var
- User is created as Active immediately
- No auto-creation without the proxy header (prevents spoofing)

**Config**:
```
EX_GOCD_ADMIN_USERS=admin@example.com,lead@example.com
EX_GOCD_AUTH_MODE=proxy  # proxy | local | none
EX_GOCD_AUTO_CREATE_USERS=true  # default: false
```

### Phase 5: Observability for Test Jobs

1. **Log view**: Per-agent console log on test job runs
2. **Dedicated test pipeline**: A synthetic pipeline that shows all agent test results
3. **Agent health dashboard**: Shows last test job result per agent

---

## Part C: GoCD Environment Feature Reference

From GoCD source (`EnvironmentConfig`, `EnvironmentsConfig`, `EnvironmentVariable`):

| GoCD Feature | Our Status |
|-------------|-----------|
| Named environment with pipelines + agents | ✅ Schema exists |
| Environment variables (secure + plain) | ❌ |
| Pipeline→environment restriction (only env agents get jobs) | ❌ |
| Agent→environment auto-assignment | ❌ |
| Environment XML config serialization | ❌ |
| Environment in pipeline config API | ⚠️ Partial |
| Environment LiveView/UI | ❌ |

## Part D: Priority Matrix

| Priority | Item | Effort |
|----------|------|--------|
| **P0** | Fix schedule_test_job | S |
| **P0** | Fix guest admin (DONE) | S |
| **P1** | Run on all agents | M |
| **P1** | Environment scheduling | M |
| **P2** | OAuth2 auto-create users | S |
| **P2** | Pre-seeded admin | S |
| **P2** | Environment UI | L |
| **P3** | Test job observability | M |
| **P3** | Agent health dashboard | M |
