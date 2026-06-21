# OAuth2-Proxy + ExGoCD Demo

Self-contained demo using the real [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) Docker image with htpasswd authentication — no external OAuth provider needed.

## Quick Start

```bash
# 1. Start ExGoCD
mix phx.server

# 2. Start oauth2-proxy (in another terminal)
docker compose up

# 3. Open http://localhost:4180
#    Login with: admin@exgocd.local / admin123

# 4. Stop
docker compose down
```

## Test Users

| Email | Password | Role |
|-------|----------|------|
| admin@exgocd.local | admin123 | admin |
| dev@exgocd.local | dev123 | developer |

## How It Works

```
Browser → oauth2-proxy (:4180) → ExGoCD (:4000)
                │
                ├─ htpasswd auth (no external provider)
                ├─ Sets X-Forwarded-User header
                ├─ Sets X-Forwarded-Email header
                └─ Sets X-Forwarded-Roles header

ExGoCD AuthHeaderPlug:
  ├─ Reads X-Forwarded-User header
  ├─ EX_GOCD_AUTO_CREATE_USERS=true → auto-creates user in DB
  ├─ EX_GOCD_ADMIN_USERS=admin@exgocd.local → admin role
  └─ Guest admin when no admin configured (open mode)
```

## Auto-Provisioning Users

To enable auto-creation of users from oauth2-proxy headers, set in your environment:

```bash
export EX_GOCD_AUTO_CREATE_USERS=true
export EX_GOCD_ADMIN_USERS=admin@exgocd.local,lead@example.com
```

- `EX_GOCD_AUTO_CREATE_USERS=true` — auto-create users who authenticate via proxy
- `EX_GOCD_ADMIN_USERS` — comma-separated list of usernames that get admin role

## Production Use

For production, replace htpasswd with a real OAuth provider (GitHub, Google, etc.):

```yaml
environment:
  OAUTH2_PROXY_PROVIDER: "github"
  OAUTH2_PROXY_GITHUB_ORG: "myorg"
  OAUTH2_PROXY_CLIENT_ID: "${GITHUB_CLIENT_ID}"
  OAUTH2_PROXY_CLIENT_SECRET: "${GITHUB_CLIENT_SECRET}"
  OAUTH2_PROXY_COOKIE_SECRET: "${COOKIE_SECRET}"
```

## Files

- `docker-compose.yml` — oauth2-proxy service configuration
- `htpasswd.txt` — bcrypt-hashed test user credentials
