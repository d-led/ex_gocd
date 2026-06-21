# Docker Compose Examples

Three scenarios for testing and evaluating the ex_gocd rewrite against official GoCD.

## 1. Official GoCD server + ex_gocd Go agent

```bash
cd examples/docker/gocd-server-ex-agent
docker compose up
```

- GoCD dashboard: http://localhost:8153
- Our Go agent auto-registers with the official GoCD server
- Verify our agent can execute jobs dispatched by GoCD

## 2. ex_gocd server + ex_gocd Go agent

```bash
cd examples/docker/exgocd-server-ex-agent
docker compose up
```

- ex_gocd dashboard: http://localhost:4000
- Full ex_gocd stack: Phoenix server + PostgreSQL + Go agent
- Our agent auto-registers with our server via the demo cookie

## 3. ex_gocd server + official GoCD Java agent

```bash
cd examples/docker/exgocd-server-gocd-agent
docker compose up
```

- ex_gocd dashboard: http://localhost:4000
- Official GoCD Java agent (gocd/gocd-agent-alpine:v25.4.0) connects to our server
- Verify the official Java agent can register and execute jobs on our server

## Post-setup

After starting any scenario:

1. Log in to the dashboard (ex_gocd: any user is admin in demo mode; GoCD: default admin/password)
2. Create a pipeline with a single stage/job (e.g., `echo "hello"`)
3. Trigger the pipeline — verify the agent picks up and executes the job
4. Check console output in the job details page
