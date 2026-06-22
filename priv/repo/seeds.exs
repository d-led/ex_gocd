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

# ── ex_gocd pipeline: dogfooding — builds & tests this very repo ────────
# Stage "ci": two parallel jobs — test (elixir+postgres) and quality (elixir).
# Agent work dir must be the repo root for mix commands to work.
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

  # test job: clone → deps → compile → test (--warnings-as-errors)
  for {cmd, args} <- [
    {"git", ["clone", "https://github.com/d-led/ex_gocd.git", "."]},
    {"mix", ["deps.get"]},
    {"mix", ["do", "compile", "--warnings-as-errors"]},
    {"mix", ["test"]}
  ] do
    %Task{}
    |> Task.changeset(%{type: "exec", command: cmd, arguments: args, job_id: job_test.id})
    |> Repo.insert!()
  end

  # quality job: clone → credo → dialyzer
  for {cmd, args} <- [
    {"git", ["clone", "https://github.com/d-led/ex_gocd.git", "."]},
    {"mix", ["deps.get"]},
    {"mix", ["credo", "--strict"]},
    {"mix", ["dialyzer"]}
  ] do
    %Task{}
    |> Task.changeset(%{type: "exec", command: cmd, arguments: args, job_id: job_quality.id})
    |> Repo.insert!()
  end

  IO.puts("Seeded dogfood pipeline: ex_gocd (ci: test + quality)")
else
  IO.puts("Pipeline 'ex_gocd' already exists, skipping seed")
end

# ── Config repo seed: dogfood our own repo ──────────────────────────────
alias ExGoCD.ConfigRepos.ConfigRepo

unless Repo.get_by(ConfigRepo, url: "https://github.com/d-led/ex_gocd.git") do
  %ConfigRepo{}
  |> ConfigRepo.changeset(%{
    url: "https://github.com/d-led/ex_gocd.git",
    branch: "main",
    source_type: "gocd_pipeline",
    material_type: "git"
  })
  |> Repo.insert!()

  IO.puts("Seeded config repo: github.com/d-led/ex_gocd (dogfooding)")
else
  IO.puts("Config repo already seeded, skipping")
end

# ── Fan-in / Fan-out demo: chained pipelines ────────────────────────────
# upstream-pipeline produces artifacts → downstream-pipeline consumes them
alias ExGoCD.Pipelines.Material

# Upstream: builds a library
unless Repo.get_by(Pipeline, name: "upstream-lib") do
  up = %Pipeline{}
    |> Pipeline.changeset(%{name: "upstream-lib", group: "demo"})
    |> Repo.insert!()

  up_stage = %Stage{}
    |> Stage.changeset(%{name: "build", pipeline_id: up.id, approval_type: "success"})
    |> Repo.insert!()

  up_job = %Job{}
    |> Job.changeset(%{name: "compile", stage_id: up_stage.id, resources: ["elixir"]})
    |> Repo.insert!()

  %Task{}
    |> Task.changeset(%{type: "exec", command: "echo", arguments: ["built lib v1.0"], job_id: up_job.id})
    |> Repo.insert!()

  # Add git material to upstream
  Repo.insert!(%Material{} |> Material.changeset(%{
    type: "git", url: "https://github.com/d-led/ex_gocd.git",
    branch: "main", pipeline_id: up.id
  }))

  IO.puts("Seeded: upstream-lib pipeline (fan-out source)")
else
  IO.puts("Pipeline 'upstream-lib' already exists")
end

# Downstream: depends on upstream-lib output
unless Repo.get_by(Pipeline, name: "downstream-app") do
  down = %Pipeline{}
    |> Pipeline.changeset(%{name: "downstream-app", group: "demo"})
    |> Repo.insert!()

  down_stage = %Stage{}
    |> Stage.changeset(%{name: "package", pipeline_id: down.id, approval_type: "success"})
    |> Repo.insert!()

  down_job = %Job{}
    |> Job.changeset(%{name: "bundle", stage_id: down_stage.id, resources: ["elixir"]})
    |> Repo.insert!()

  %Task{}
    |> Task.changeset(%{type: "exec", command: "echo", arguments: ["packaged app with upstream lib"], job_id: down_job.id})
    |> Repo.insert!()

  # Add pipeline material: depends on upstream-lib
  up = Repo.get_by!(Pipeline, name: "upstream-lib")
  Repo.insert!(%Material{} |> Material.changeset(%{
    type: "pipeline", pipeline_name: "upstream-lib", stage_name: "build",
    pipeline_id: down.id
  }))

  IO.puts("Seeded: downstream-app pipeline (fan-in: depends on upstream-lib)")
else
  IO.puts("Pipeline 'downstream-app' already exists")
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
