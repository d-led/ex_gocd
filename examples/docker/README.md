# Docker Compose Examples

Ready-to-run stacks demonstrating ex_gocd in three configurations. Start with `docker compose up` — no manual setup needed.

## Quick Reference

| Example | Dashboard        | Server Port(s) | DB Port | Server              | Agent              |
|---------|-----------------|-----------------|---------|---------------------|--------------------|
| 1       | GoCD             | 8153, 8154      | —       | Official GoCD       | ex_gocd Go agent   |
| 2       | ex_gocd          | 4002            | 5433    | ex_gocd Phoenix     | ex_gocd Go agent   |
| 3       | ex_gocd          | 4003            | 5434    | ex_gocd Phoenix     | Official Java agent|

Ports are deliberately non-colliding with the main `docker-compose.yml` (5432, 3000, 4317, 16686, etc.).

## Automated Exercise

Run all examples sequentially with milestone verification:

```bash
./exercise_all.sh
```

Each example: start → verify server health → verify agent idle → (ex_gocd) schedule pipeline & verify completion → tear down.

Requires: `docker`, `curl`, `python3`, `psql`.

---

## 1. Official GoCD server + ex_gocd Go agent

```bash
cd examples/docker/gocd-server-ex-agent
docker compose up
```

- GoCD dashboard: http://localhost:8153
- Our Go agent auto-registers with the official GoCD server (key: `123456789abcdef`)
- Proves our agent speaks the real GoCD wire protocol

## 2. ex_gocd server + ex_gocd Go agent

```bash
cd examples/docker/exgocd-server-ex-agent
docker compose up
```

- ex_gocd dashboard: http://localhost:4002
- Full ex_gocd stack: Phoenix server + PostgreSQL + Go agent
- Agent auto-registers via demo cookie `ex-gocd-demo-cookie`

## 3. ex_gocd server + official GoCD Java agent

```bash
cd examples/docker/exgocd-server-gocd-agent
docker compose up
```

- ex_gocd dashboard: http://localhost:4003
- Official GoCD Java agent connects to our server
- Proves our server speaks the real GoCD agent protocol

## Manual Pipeline Test

After starting any ex_gocd example:

```bash
# Trigger a demo job (server will dispatch to the idle agent)
curl -X POST http://localhost:4002/api/jobs/schedule \
  -H "Content-Type: application/json" \
  -d '{"pipeline":"demo","stage":"build","job":"default","resources":["go"]}'

# Check stats
curl http://localhost:4002/api/stats

# Check result in DB (postgres port mapped to 5433 for example 2)
PGPASSWORD=postgres psql -h localhost -p 5433 -U postgres -d ex_gocd_prod \
  -c "SELECT pipeline_name, state, result FROM agent_job_runs ORDER BY inserted_at DESC LIMIT 5;"
```
