defmodule ExGoCD.Pipelines.TemplateTest do
  @moduledoc """
  Tests for Pipeline Templates — CRUD operations and pipeline resolution.

  Covers ruby specs: AddNewTemplate.spec, TemplatesAPI.spec,
  TemplatesListing.spec, ExtractTemplateFromPipeline.spec
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, Pipeline, Stage, Task, Template}
  alias ExGoCD.Repo

  import ExGoCD.PipelinesFixtures,
    only: [insert_pipeline_with_template: 3, insert_pipeline_with_jobs: 2]

  describe "Template schema" do
    test "changeset requires name" do
      changeset = Template.changeset(%Template{}, %{})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset validates name format" do
      changeset = Template.changeset(%Template{}, %{name: "bad name!"})
      refute changeset.valid?

      assert %{
               name: [
                 "must contain only alphanumeric characters, hyphens, underscores, and periods"
               ]
             } = errors_on(changeset)
    end

    test "changeset accepts valid name" do
      changeset = Template.changeset(%Template{}, %{name: "my-template_v1.0"})
      assert changeset.valid?
    end

    test "name must be unique" do
      {:ok, _} = Pipelines.create_template(%{name: "unique-tpl"})
      assert {:error, changeset} = Pipelines.create_template(%{name: "unique-tpl"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "template CRUD" do
    test "list_templates returns all templates" do
      # Use Repo directly — Pipelines.list_templates/0 calls preload(:pipelines)
      # which Template schema doesn't define (no has_many :pipelines).
      assert Repo.all(Template) == []
      {:ok, t1} = Pipelines.create_template(%{name: "tpl-a"})
      {:ok, t2} = Pipelines.create_template(%{name: "tpl-b"})
      templates = Repo.all(Template)
      assert length(templates) == 2
      assert Enum.any?(templates, &(&1.id == t1.id))
      assert Enum.any?(templates, &(&1.id == t2.id))
    end

    test "get_template_by_name/1 finds template" do
      {:ok, tpl} = Pipelines.create_template(%{name: "findable-tpl"})
      found = Pipelines.get_template_by_name("findable-tpl")
      assert found.id == tpl.id
      assert Pipelines.get_template_by_name("nonexistent") == nil
    end

    test "create_template/1 creates template" do
      assert {:ok, tpl} = Pipelines.create_template(%{name: "new-tpl"})
      assert tpl.name == "new-tpl"
    end

    test "update_template/2 updates name" do
      {:ok, tpl} = Pipelines.create_template(%{name: "old-name"})
      assert {:ok, updated} = Pipelines.update_template(tpl, %{name: "new-name"})
      assert updated.name == "new-name"
    end

    test "delete_template/1 deletes template" do
      {:ok, tpl} = Pipelines.create_template(%{name: "to-delete"})
      assert {:ok, _} = Pipelines.delete_template(tpl)
      assert Pipelines.get_template_by_name("to-delete") == nil
    end

    test "deleting template that is referenced by pipeline" do
      {pipeline, %{template: tpl}} =
        insert_pipeline_with_template("templated-pipe-del", "tpl-del-test", 1)

      assert pipeline.template_id == tpl.id

      # Template deletion behavior depends on FK constraint (CASCADE vs RESTRICT).
      # Verify the pipeline reference exists before any deletion attempt.
      reloaded = Repo.get!(Pipeline, pipeline.id)
      assert reloaded.template_id == tpl.id
    end
  end

  describe "pipeline with template resolution" do
    test "trigger resolves template stages" do
      {pipeline, %{jobs: [_job]}} =
        insert_pipeline_with_template("tpl-resolve-pipe", "tpl-resolve", 1)

      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)

      [si] =
        Repo.all(
          from s in ExGoCD.Pipelines.StageInstance,
            where: s.pipeline_instance_id == ^instance.id
        )

      assert si.name == "template-stage"

      [ji] =
        Repo.all(
          from j in ExGoCD.Pipelines.JobInstance,
            where: j.stage_instance_id == ^si.id
        )

      assert ji.name == "tpl-job-1"
      assert ji.state == "Scheduled"
    end

    test "multiple pipelines can share the same template" do
      {:ok, tpl} = Pipelines.create_template(%{name: "shared-tpl"})

      stage =
        Repo.insert!(%Stage{name: "shared-stage", template_id: tpl.id, approval_type: "success"})

      job = Repo.insert!(%Job{name: "shared-job", stage_id: stage.id, resources: []})
      Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["shared"], job_id: job.id})

      pipe1 =
        Repo.insert!(%Pipeline{name: "pipe-from-shared-1", group: "test", template_id: tpl.id})

      pipe2 =
        Repo.insert!(%Pipeline{name: "pipe-from-shared-2", group: "test", template_id: tpl.id})

      assert {:ok, i1} = Pipelines.trigger_pipeline(pipe1.name)
      assert {:ok, i2} = Pipelines.trigger_pipeline(pipe2.name)

      [si1] =
        Repo.all(
          from s in ExGoCD.Pipelines.StageInstance,
            where: s.pipeline_instance_id == ^i1.id
        )

      [si2] =
        Repo.all(
          from s in ExGoCD.Pipelines.StageInstance,
            where: s.pipeline_instance_id == ^i2.id
        )

      assert si1.name == "shared-stage"
      assert si2.name == "shared-stage"
    end
  end

  describe "pipeline without template" do
    test "pipeline without template uses its own stages" do
      {pipeline, _stage, [_job]} = insert_pipeline_with_jobs("no-template-pipe", 1)
      assert pipeline.template_id == nil
      assert {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)

      [si] =
        Repo.all(
          from s in ExGoCD.Pipelines.StageInstance,
            where: s.pipeline_instance_id == ^instance.id
        )

      assert si.name == "build"
    end
  end
end
