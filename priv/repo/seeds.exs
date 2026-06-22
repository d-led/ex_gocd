# Script for populating the database. You can run it with:
#   mix run priv/repo/seeds.exs

alias ExGoCD.Repo
alias ExGoCD.Pipelines.{Pipeline, Stage, Job, Task, Material}
import Ecto.Query, only: [from: 2]

ensure_material = fn pipeline, type, url ->
  branch = "main"
  mat =
    case Repo.one(from(m in Material, where: m.type == ^type and m.url == ^url, limit: 1)) do
      nil ->
        mat = Repo.insert!(%Material{} |> Material.changeset(%{type: type, url: url, branch: branch}))
        mat
      existing ->
        existing
    end

  # Link pipeline to this material if not already linked
  linked? = Repo.exists?(
    from(pm in "pipelines_materials",
    where: pm.pipeline_id == ^pipeline.id and pm.material_id == ^mat.id)
  )

  unless linked? do
    Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: mat.id}])
  end

  mat
end

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

  ensure_material.(pipeline, "git", "https://github.com/d-led/ex_gocd.git")

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

  ensure_material.(pipeline, "git", "https://github.com/d-led/ex_gocd.git")

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

  ensure_material.(pipeline, "git", "https://github.com/d-led/ex_gocd.git")

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

# ── Fan-in / Fan-out demo: classic GoCD gate pattern ──────────────────
# Pattern: C1 → (C2, C3) → Package (gate)
# C1 = upstream-lib: builds a shared library
# C2 = component-a: fan-out, depends on upstream-lib
# C3 = component-b: fan-out, depends on upstream-lib
# Package = integration-pipeline: fan-in gate, waits for both C2 AND C3 green
alias ExGoCD.Pipelines.Material

defmodule Seeds.FanInOut do
  def create_pipeline(name, group, stage_name, job_name, task_cmd, materials \\ []) do
    p = %Pipeline{}
      |> Pipeline.changeset(%{name: name, group: group})
      |> Repo.insert!()

    s = %Stage{}
      |> Stage.changeset(%{name: stage_name, pipeline_id: p.id, approval_type: "success"})
      |> Repo.insert!()

    j = %Job{}
      |> Job.changeset(%{name: job_name, stage_id: s.id, resources: ["elixir"]})
      |> Repo.insert!()

    %Task{}
      |> Task.changeset(%{type: "exec", command: "echo", arguments: [task_cmd], job_id: j.id})
      |> Repo.insert!()

    Enum.each(materials, fn mat ->
      material = Repo.insert!(%Material{} |> Material.changeset(mat))
      # Populate many-to-many join table (Material uses join_through: "pipelines_materials")
      Repo.insert_all("pipelines_materials", [%{pipeline_id: p.id, material_id: material.id}])
    end)

    p
  end
end

# C1: upstream-lib — builds shared library
unless Repo.get_by(Pipeline, name: "upstream-lib") do
  Seeds.FanInOut.create_pipeline("upstream-lib", "demo", "build", "compile",
    "built lib v1.0",
    [%{type: "git", url: "https://github.com/d-led/ex_gocd.git", branch: "main"}])
  IO.puts("Seeded: upstream-lib (C1 — fan-out source)")
else
  IO.puts("Pipeline 'upstream-lib' already exists")
end

# C2: component-a — fan-out, depends on upstream-lib
unless Repo.get_by(Pipeline, name: "component-a") do
  _up = Repo.get_by!(Pipeline, name: "upstream-lib")
  Seeds.FanInOut.create_pipeline("component-a", "demo", "build", "test",
    "tested component-a with lib",
    [%{type: "dependency", url: "upstream-lib", branch: "build"}])
  IO.puts("Seeded: component-a (C2 — fan-out from upstream-lib)")
else
  IO.puts("Pipeline 'component-a' already exists")
end

# C3: component-b — fan-out, depends on upstream-lib
unless Repo.get_by(Pipeline, name: "component-b") do
  _up = Repo.get_by!(Pipeline, name: "upstream-lib")
  Seeds.FanInOut.create_pipeline("component-b", "demo", "build", "test",
    "tested component-b with lib",
    [%{type: "dependency", url: "upstream-lib", branch: "build"}])
  IO.puts("Seeded: component-b (C3 — fan-out from upstream-lib)")
else
  IO.puts("Pipeline 'component-b' already exists")
end

# Package: integration-pipeline — fan-in gate, depends on BOTH component-a AND component-b
unless Repo.get_by(Pipeline, name: "integration-pipeline") do
  Seeds.FanInOut.create_pipeline("integration-pipeline", "demo", "integrate", "package",
    "packaged integration with all components",
    [
      %{type: "dependency", url: "component-a", branch: "build"},
      %{type: "dependency", url: "component-b", branch: "build"}
    ])
  IO.puts("Seeded: integration-pipeline (fan-in gate — depends on component-a + component-b)")
else
  IO.puts("Pipeline 'integration-pipeline' already exists")
end

# Keep backward compat: downstream-app (simple chain)
unless Repo.get_by(Pipeline, name: "downstream-app") do
  _up = Repo.get_by!(Pipeline, name: "upstream-lib")
  Seeds.FanInOut.create_pipeline("downstream-app", "demo", "package", "bundle",
    "packaged app with upstream lib",
    [%{type: "dependency", url: "upstream-lib", branch: "build"}])
  IO.puts("Seeded: downstream-app (legacy chain)")
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

# ── Ensure all pipelines have at least a git material ───────────────────
# Runs every seed (not guarded) to fix pipelines created before the join-table fix

Repo.all(from p in Pipeline, preload: [:materials])
|> Enum.each(fn p ->
  if Enum.empty?(p.materials) do
    ensure_material.(p, "git", "https://github.com/d-led/ex_gocd.git")
    IO.puts("  + added git material to #{p.name}")
  end
end)
