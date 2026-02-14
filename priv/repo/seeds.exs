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

# CI pipeline (GoCD-style): two jobs in first stage — one no resources, one requires linux+docker
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
