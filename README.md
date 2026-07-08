# ExGoCD

**A Phoenix LiveView rewrite of Thoughtworks GoCD** — distributed CI/CD with
plugin extensibility, built-in observability, and a Go-powered agent.

[![Quality Gate](https://img.shields.io/badge/quality-17%2F17-brightgreen)]()
[![Tests](https://img.shields.io/badge/tests-949%20passed-brightgreen)]()
[![Cypress](https://img.shields.io/badge/e2e-16%20specs-brightgreen)]()

---

## Quick Start

```bash
mix setup              # install deps, create DB
mix phx.server         # start at localhost:4000
```

### With Go agents (process-compose)

```bash
docker compose up -d postgres jaeger otel-collector
process-compose up
```

Starts Phoenix server + CI agent (elixir,postgres) + Docker agent (docker).
See `process-compose.yaml`.

## Features

**Full GoCD parity** — pipelines, stages, jobs, materials, VSM, analytics,
config-as-code, elastic agents, RBAC, and more. See [PARITY.md](docs/PARITY.md).

| Area | Highlights |
|------|-----------|
| Pipeline engine | Scheduling, fan-in, config diff, locking, manual/auto trigger |
| Agents | WebSocket protocol, Go binary (~10MB), elastic (K8s + Docker) |
| UI | LiveView dashboard, stage overview popups, Gantt charts, VSM |
| Config | XML import/export, YAML config repos, templates, wizard |
| Observability | Built-in OpenTelemetry, Jaeger traces, Grafana dashboards |
| Plugins | Standalone OTP apps — agent selectors, org hierarchy, auth |
| Security | RBAC with Bodyguard, per-environment policies, PAT, encryption |

## Stack

| Layer | Tech |
|-------|------|
| Server | Elixir + Phoenix LiveView + Ecto (PostgreSQL) |
| Agents | Go — statically linked, no cgo |
| Plugins | Standalone OTP apps via libcluster |
| Frontend | Phoenix LiveView + Tailwind CSS + daisyUI |
| Ops | OpenTelemetry, Jaeger, Grafana, Docker Compose |

## Services

| Service | URL |
|---------|-----|
| **ex_gocd** | [localhost:4000](http://localhost:4000) |
| **Adminer** (DB) | [localhost:8092](http://localhost:8092/?pgsql=postgres&username=postgres&db=postgres&ns=public) |
| **Grafana** | [localhost:3000](http://localhost:3000) |
| **Jaeger** (traces) | [localhost:16686](http://localhost:16686/search) |
| **smtp4dev** (email) | [localhost:8025](http://localhost:8025) |

## Testing

```bash
mix test                              # full suite (needs Postgres)
EX_GOCD_TEST_NO_DB=1 mix test_no_db   # skip DB tests
bash scripts/quality-gate.sh          # all static analysis + tests
```

## Docs

- [Feature Parity & Architecture](docs/PARITY.md)
- [Plugin Authoring Guide](docs/plugin_authoring.md)
- [Module Mapping](docs/module_mapping.md) — Elixir ↔ GoCD Java
- [Agent Implementation](agent/README.md)

## License

Mozilla Public License 2.0 — see [LICENSE](LICENSE).
