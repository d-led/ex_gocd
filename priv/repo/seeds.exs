# Script for populating the database. You can run it with:
#   mix run priv/repo/seeds.exs

alias ExGoCD.Repo
alias ExGoCD.Pipelines.{Pipeline, Stage, Job, Task}

# Demo pipeline: one stage "build", one job "default", one exec task
unless Repo.get_by(Pipeline, name: "demo") do
  pipeline =
    %Pipeline{}
    |> Pipeline.changeset(%{name: "demo", group: "default"})
    |> Repo.insert!()

  stage =
    %Stage{}
    |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"})
    |> Repo.insert!()

  job =
    %Job{}
    |> Job.changeset(%{name: "default", stage_id: stage.id, resources: []})
    |> Repo.insert!()

  %Task{}
  |> Task.changeset(%{
    type: "exec",
    command: "echo",
    arguments: ["hello from pipeline demo"],
    job_id: job.id
  })
  |> Repo.insert!()

  IO.puts("Seeded pipeline: demo (stage: build, job: default)")
else
  IO.puts("Pipeline 'demo' already exists, skipping seed")
end

# CI pipeline — two jobs in one stage: compile+test and quality
unless Repo.get_by(Pipeline, name: "ci") do
  pipeline =
    %Pipeline{}
    |> Pipeline.changeset(%{name: "ci", group: "default"})
    |> Repo.insert!()

  stage =
    %Stage{}
    |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"})
    |> Repo.insert!()

  job_unit =
    %Job{}
    |> Job.changeset(%{name: "unit", stage_id: stage.id, resources: []})
    |> Repo.insert!()

  job_integration =
    %Job{}
    |> Job.changeset(%{name: "integration", stage_id: stage.id, resources: ["linux", "docker"]})
    |> Repo.insert!()

  for {job, msg} <- [{job_unit, "unit tests"}, {job_integration, "integration tests"}] do
    %Task{}
    |> Task.changeset(%{
      type: "exec",
      command: "echo",
      arguments: [msg],
      job_id: job.id
    })
    |> Repo.insert!()
  end

  IO.puts("Seeded pipeline: ci (stage: build, jobs: unit [no resources], integration [linux,docker])")
else
  IO.puts("Pipeline 'ci' already exists, skipping seed")
end

# ── ex_gocd pipeline: builds & tests this very repo ──────────────────────
# Stage "ci": two parallel jobs — compile+test (runs mix test) and quality (credo+dialyzer).
# Agent must have resource "elixir" and work dir set to the repo root.
unless Repo.get_by(Pipeline, name: "ex_gocd") do
  pipeline =
    %Pipeline{}
    |> Pipeline.changeset(%{name: "ex_gocd", group: "default", label_template: "${COUNT}"})
    |> Repo.insert!()

  stage =
    %Stage{}
    |> Stage.changeset(%{name: "ci", pipeline_id: pipeline.id, approval_type: "success"})
    |> Repo.insert!()

  job_test =
    %Job{}
    |> Job.changeset(%{name: "test", stage_id: stage.id, resources: ["elixir", "postgres"]})
    |> Repo.insert!()

  job_quality =
    %Job{}
    |> Job.changeset(%{name: "quality", stage_id: stage.id, resources: ["elixir"]})
    |> Repo.insert!()

  # test job: deps → compile → test
  for {cmd, args} <- [
    {"mix", ["deps.get"]},
    {"mix", ["compile"]},
    {"mix", ["test"]}
  ] do
    %Task{}
    |> Task.changeset(%{type: "exec", command: cmd, arguments: args, job_id: job_test.id})
    |> Repo.insert!()
  end

  # quality job: credo → dialyzer
  for {cmd, args} <- [
    {"mix", ["credo", "--strict"]},
    {"mix", ["dialyzer"]}
  ] do
    %Task{}
    |> Task.changeset(%{type: "exec", command: cmd, arguments: args, job_id: job_quality.id})
    |> Repo.insert!()
  end

  IO.puts("Seeded pipeline: ex_gocd (stage: ci, jobs: test [elixir,postgres], quality [elixir])")
else
  IO.puts("Pipeline 'ex_gocd' already exists, skipping seed")
end

alias ExGoCD.AgentJobRuns.AgentJobRun

unless Repo.get_by(AgentJobRun, build_id: "demo-build-1") do
  %AgentJobRun{}
  |> AgentJobRun.changeset(%{
    agent_uuid: "00000000-0000-0000-0000-000000000001",
    build_id: "demo-build-1",
    pipeline_name: "demo",
    pipeline_counter: 1,
    stage_name: "build",
    stage_counter: 1,
    job_name: "default",
    state: "Completed",
    result: "Passed",
    console_log: "Hello, this is a mock console log from the seeds script!\n"
  })
  |> Repo.insert!()

  IO.puts("Seeded mock agent job run for build-agent-01.example.com")
else
  IO.puts("Mock job run already exists, skipping seed")
end

# Seed default users
alias ExGoCD.Accounts

unless Repo.get_by(ExGoCD.Accounts.User, username: "admin") do
  {:ok, _} = Accounts.create_user(%{
    username: "admin",
    display_name: "System Administrator",
    roles: ["admin", "developer"],
    status: "Active"
  })
  IO.puts("Seeded user: admin")
end

unless Repo.get_by(ExGoCD.Accounts.User, username: "developer") do
  {:ok, _} = Accounts.create_user(%{
    username: "developer",
    display_name: "Lead Developer",
    roles: ["developer"],
    status: "Active"
  })
  IO.puts("Seeded user: developer")
end

unless Repo.get_by(ExGoCD.Accounts.User, username: "viewer") do
  {:ok, _} = Accounts.create_user(%{
    username: "viewer",
    display_name: "Guest Viewer",
    roles: [],
    status: "Active"
  })
  IO.puts("Seeded user: viewer")
end
