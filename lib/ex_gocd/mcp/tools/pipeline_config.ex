defmodule ExGoCD.Mcp.Tools.PipelineConfig do
  @moduledoc """
  Authoring: creating a pipeline from a description, changing its own settings,
  and deleting it.

  A pipeline is a tree — stages, jobs, tasks, materials — and creating one is
  several inserts that must all happen or none of them. The create tool does
  them in one transaction, so a definition with a typo in its third stage leaves
  nothing behind; and every refusal says which stage or job the typo was in,
  because "name: has already been taken" without a stage name is a puzzle.

  Deliberately not here: rewriting an existing pipeline's stages. A stage's job
  instances are keyed to the stage row, so replacing a stage is a migration
  rather than an edit; `gocd_update_pipeline` changes the pipeline's own
  settings and says so.
  """

  alias ExGoCD.{AuditLog.Events, ConfigAudit, Pipelines, Repo}
  alias ExGoCD.Mcp.{Args, Auth, Changeset, Render, Tool}

  @names ~w(gocd_create_pipeline gocd_update_pipeline gocd_delete_pipeline)

  @definition %{
    "type" => "object",
    "description" =>
      "The pipeline to create: `name`, and `stages`; optionally `group`, " <>
        "`label_template`, `lock_behavior`, `timer`, `parameters`, " <>
        "`environment_variables` and `materials`.",
    "properties" => %{
      "name" => %{"type" => "string", "description" => "Letters, digits, `-`, `_` and `.`."},
      "group" => %{
        "type" => "string",
        "description" => "The pipeline group. Default `defaultGroup`."
      },
      "label_template" => %{"type" => "string", "description" => "Default `${COUNT}`."},
      "lock_behavior" => %{
        "type" => "string",
        "enum" => ["none", "lockOnFailure", "unlockWhenFinished"]
      },
      "timer" => %{"type" => "string", "description" => "A cron expression, e.g. `0 0 3 * * ?`."},
      "parameters" => %{
        "type" => "object",
        "additionalProperties" => %{"type" => "string"},
        "description" => "Pipeline parameters, name to value."
      },
      "environment_variables" => %{
        "type" => "object",
        "additionalProperties" => %{"type" => "string"},
        "description" => "Plain environment variables, name to value."
      },
      "materials" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{
              "type" => "string",
              "description" => "`git`, `svn`, `hg`, or `dependency`."
            },
            "url" => %{
              "type" => "string",
              "description" => "The repository url, or the upstream pipeline for a dependency."
            },
            "branch" => %{"type" => "string"},
            "destination" => %{"type" => "string"}
          },
          "required" => ["url"]
        }
      },
      "stages" => %{
        "type" => "array",
        "description" => "In the order they run. At least one.",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "approval_type" => %{
              "type" => "string",
              "enum" => ["success", "manual"],
              "description" => "`success` runs on its own; `manual` waits for a person."
            },
            "jobs" => %{
              "type" => "array",
              "description" => "At least one, each with at least one task.",
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "name" => %{"type" => "string"},
                  "resources" => %{
                    "type" => "array",
                    "items" => %{"type" => "string"},
                    "description" => "Resource tags an agent must have."
                  },
                  "tasks" => %{
                    "type" => "array",
                    "items" => %{
                      "type" => "object",
                      "properties" => %{
                        "type" => %{"type" => "string", "description" => "Default `exec`."},
                        "command" => %{"type" => "string"},
                        "arguments" => %{"type" => "array", "items" => %{"type" => "string"}},
                        "working_directory" => %{"type" => "string"},
                        "run_if" => %{
                          "type" => "string",
                          "enum" => ["passed", "failed", "any"],
                          "description" => "Default `passed`."
                        }
                      }
                    }
                  }
                },
                "required" => ["name", "tasks"]
              }
            }
          },
          "required" => ["name", "jobs"]
        }
      }
    },
    "required" => ["name", "stages"]
  }

  @tools [
    %{
      "name" => "gocd_create_pipeline",
      "title" => "Create a pipeline",
      "description" =>
        "Creates a pipeline from a description: its stages in order, each stage's jobs, each " <>
          "job's tasks, and its materials. All of it happens in one transaction — a definition " <>
          "that is wrong in the third stage creates nothing. Refuses a name that already " <>
          "exists (`gocd_update_pipeline` changes one) and says which stage or job a refusal " <>
          "was about. An administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"definition" => @definition},
        "required" => ["definition"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_update_pipeline",
      "title" => "Change a pipeline's own settings",
      "description" =>
        "Changes the pipeline itself — its group, label template, lock behaviour, paused " <>
          "state, timer, parameters and environment variables — and nothing in its stages. " <>
          "That is the honest boundary: a stage's run history is keyed to the stage row, so " <>
          "rewriting stages is a migration, not an edit. `gocd_describe_pipeline` shows what " <>
          "a pipeline is made of. An administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "group" => %{"type" => "string"},
          "label_template" => %{"type" => "string"},
          "lock_behavior" => %{
            "type" => "string",
            "enum" => ["none", "lockOnFailure", "unlockWhenFinished"]
          },
          "paused" => %{"type" => "boolean"},
          "timer" => %{
            "type" => "string",
            "description" => "A cron expression, or empty to remove it."
          },
          "parameters" => %{
            "type" => "object",
            "additionalProperties" => %{"type" => "string"},
            "description" => "Replaces the pipeline's parameters."
          },
          "environment_variables" => %{
            "type" => "object",
            "additionalProperties" => %{"type" => "string"},
            "description" => "Replaces the pipeline's plain environment variables."
          }
        },
        "required" => ["name"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_delete_pipeline",
      "title" => "Delete a pipeline",
      "description" =>
        "Deletes a pipeline and its configuration. Its run history goes with it — the " <>
          "instances and their stages and jobs are deleted with the pipeline. Answers what " <>
          "would be deleted unless `confirm` is true. An administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "confirm" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "True deletes; false only reports what would be deleted."
          }
        },
        "required" => ["name"]
      },
      "annotations" => Tool.destructive()
    }
  ]

  @doc "The definitions of this family's tools."
  @spec definitions() :: [map()]
  def definitions, do: @tools

  @doc """
  The shape of a pipeline definition, for a tool that reads one the same way.
  """
  @spec definition_schema() :: map()
  def definition_schema, do: @definition

  @doc """
  Reads a definition exactly as `gocd_create_pipeline` reads it and returns what
  it understood — stages, jobs, tasks, materials — without writing anything.

  `gocd_validate_pipeline` uses this to answer "would this run?" about a
  pipeline that does not exist yet, which is the only moment the answer is free.
  """
  @spec preview(map()) :: {:ok, map()} | {:error, String.t()}
  def preview(definition) when is_map(definition), do: validate(definition)

  def preview(_other),
    do: {:error, "`definition` must be an object with at least a `name` and `stages`."}

  @doc "The names of this family's tools."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Whether this family answers to a tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: name in @names

  @doc "Calls one of this family's tools."
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call("gocd_create_pipeline", args, ctx), do: create(args, ctx)
  def call("gocd_update_pipeline", args, ctx), do: update(args, ctx)
  def call("gocd_delete_pipeline", args, ctx), do: delete(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  # ── create ─────────────────────────────────────────────────────────

  defp create(args, ctx) do
    with {:ok, definition} <- definition_arg(args),
         :ok <- Auth.require_admin(ctx.user, "create a pipeline"),
         :ok <- name_is_free(definition.name) do
      insert(definition, ctx)
    else
      {:error, message} -> {:error, message}
    end
  end

  defp name_is_free(name) do
    case Pipelines.get_pipeline_by_name(name) do
      nil ->
        :ok

      _pipeline ->
        {:error,
         "Pipeline '#{name}' already exists. `gocd_update_pipeline` changes its settings, " <>
           "`gocd_describe_pipeline` shows what it is made of."}
    end
  end

  # One transaction: a stage that fails its changeset rolls back the pipeline and
  # every stage before it, so a typo leaves no half-built pipeline behind.
  defp insert(definition, ctx) do
    result =
      Repo.transaction(fn ->
        with {:ok, pipeline} <- Pipelines.create_pipeline(pipeline_attrs(definition)),
             {:ok, materials} <- add_materials(pipeline, definition.materials),
             {:ok, stages} <- add_stages(pipeline, definition.stages) do
          %{pipeline: pipeline, materials: materials, stages: stages}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, built} -> created(built, ctx)
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Changeset.message(changeset)}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, "Could not create the pipeline: #{inspect(reason)}"}
    end
  end

  defp pipeline_attrs(definition) do
    %{
      name: definition.name,
      group: definition.group,
      label_template: definition.label_template,
      lock_behavior: definition.lock_behavior,
      timer: definition.timer,
      parameters: definition.parameters,
      environment_variables: definition.environment_variables
    }
  end

  defp add_materials(_pipeline, []), do: {:ok, []}

  defp add_materials(pipeline, materials) do
    materials
    |> Enum.reduce_while({:ok, []}, fn material, {:ok, acc} ->
      case Pipelines.create_material_for_pipeline(pipeline, material) do
        {:ok, created} -> {:cont, {:ok, [created | acc]}}
        {:error, reason} -> {:halt, {:error, material_error(material, reason)}}
      end
    end)
    |> in_order()
  end

  defp material_error(material, {:missing_pipeline, upstream}) do
    "Material #{material["url"]}: the dependency points at pipeline '#{upstream}', which " <>
      "does not exist."
  end

  defp material_error(material, %Ecto.Changeset{} = changeset),
    do: "Material #{material["url"]}: #{Changeset.message(changeset)}"

  defp material_error(material, reason),
    do: "Material #{material["url"]}: #{inspect(reason)}"

  defp add_stages(_pipeline, []), do: {:ok, []}

  defp add_stages(pipeline, stages) do
    stages
    |> Enum.reduce_while({:ok, []}, fn stage, {:ok, acc} ->
      case add_stage(pipeline, stage) do
        {:ok, built} -> {:cont, {:ok, [built | acc]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> in_order()
  end

  defp add_stage(pipeline, stage) do
    attrs = %{name: stage.name, pipeline_id: pipeline.id, approval_type: stage.approval_type}

    case Pipelines.create_stage(attrs) do
      {:ok, created} ->
        with {:ok, jobs} <- add_jobs(created, stage.jobs) do
          {:ok, %{name: created.name, approval_type: stage.approval_type, jobs: jobs}}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Stage '#{stage.name}': #{Changeset.message(changeset)}"}
    end
  end

  defp add_jobs(stage, jobs) do
    jobs
    |> Enum.reduce_while({:ok, []}, fn job, {:ok, acc} ->
      case add_job(stage, job) do
        {:ok, built} -> {:cont, {:ok, [built | acc]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> in_order()
  end

  defp add_job(stage, job) do
    attrs = %{name: job.name, stage_id: stage.id, resources: job.resources}

    case Pipelines.create_job(attrs) do
      {:ok, created} ->
        with {:ok, tasks} <- add_tasks(created, job.tasks) do
          {:ok, %{name: created.name, tasks: tasks}}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Job '#{job.name}' of stage '#{stage.name}': #{Changeset.message(changeset)}"}
    end
  end

  defp add_tasks(job, tasks) do
    tasks
    |> Enum.reduce_while({:ok, []}, fn task, {:ok, acc} ->
      case Pipelines.create_task(Map.put(task, :job_id, job.id)) do
        {:ok, created} ->
          {:cont, {:ok, [task_label(created) | acc]}}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:halt, {:error, "Task of job '#{job.name}': #{Changeset.message(changeset)}"}}
      end
    end)
    |> in_order()
  end

  defp in_order({:ok, built}), do: {:ok, Enum.reverse(built)}
  defp in_order({:error, message}), do: {:error, message}

  defp task_label(task) do
    [task.command | task.arguments || []] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end

  defp created(%{pipeline: pipeline, materials: materials, stages: stages}, ctx) do
    Events.config_changed(ctx.user.username, pipeline.name, %{
      action: "created",
      stages: Enum.map(stages, & &1.name),
      materials: Enum.map(materials, & &1.url)
    })

    jobs = stages |> Enum.flat_map(& &1.jobs) |> length()
    link = "#{ctx.base_url}/admin/pipelines/#{pipeline.name}/edit"
    fit = ConfigAudit.fit_pipeline(pipeline.name)

    Tool.ok(
      "#{pipeline.name} created in group #{Render.cell(pipeline.group)}: " <>
        "#{length(stages)} stage(s), #{jobs} job(s), #{length(materials)} material(s).\n" <>
        "Its configuration: #{link}\n" <>
        "It has not run yet; `gocd_trigger_pipeline` starts it." <>
        verdict_text(fit),
      %{
        "name" => pipeline.name,
        "group" => pipeline.group,
        "link" => link,
        "materials" => Enum.map(materials, &%{"type" => &1.type, "url" => &1.url}),
        "stages" =>
          Enum.map(stages, fn stage ->
            %{
              "name" => stage.name,
              "approval_type" => stage.approval_type,
              "jobs" => Enum.map(stage.jobs, & &1.name)
            }
          end),
        "will_run" => will_run(fit)
      }
    )
  end

  # The question an author asks the moment a pipeline exists. A pipeline that is
  # in no environment has a narrower answer than it looks: only agents outside
  # every environment can take its jobs, so a fleet that lives entirely inside
  # environments takes none of them until the pipeline is assigned to one.
  defp verdict_text(nil), do: ""

  defp verdict_text(%{jobs: []}) do
    "\nWill it run? There is nothing to run: it has no jobs."
  end

  defp verdict_text(%{jobs: jobs}) do
    case Enum.reject(jobs, &(&1.runnable != [])) do
      [] ->
        "\nWill it run? Yes — every one of its #{length(jobs)} job(s) has an agent."

      [stuck | _] ->
        "\nWill it run? Not yet — `#{stuck.stage}` / `#{stuck.job}`: #{stuck.verdict}. " <>
          "#{stuck.advice || ""} `gocd_audit_config` shows the rest."
    end
  end

  defp will_run(nil), do: nil

  defp will_run(%{jobs: jobs}) do
    stuck = Enum.reject(jobs, &(&1.runnable != []))

    %{
      "jobs" => length(jobs),
      "jobs_with_an_agent" => length(jobs) - length(stuck),
      "first_problem" =>
        case stuck do
          [] -> nil
          [first | _] -> "#{first.stage} / #{first.job}: #{first.verdict}"
        end
    }
  end

  # ── update ─────────────────────────────────────────────────────────

  defp update(args, ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         :ok <- Auth.require_admin(ctx.user, "change a pipeline's settings"),
         {:ok, attrs} <- settings(args) do
      case Pipelines.get_pipeline_by_name(name) do
        nil ->
          {:error, "Pipeline '#{name}' not found."}

        pipeline ->
          if attrs == %{} do
            {:error,
             "Nothing to change: give `group`, `label_template`, `lock_behavior`, `paused`, " <>
               "`timer`, `parameters` or `environment_variables`."}
          else
            apply_settings(pipeline, attrs, ctx)
          end
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp apply_settings(pipeline, attrs, ctx) do
    case Pipelines.update_pipeline(pipeline, attrs) do
      {:ok, updated} ->
        Events.config_changed(ctx.user.username, updated.name, %{
          action: "updated",
          fields: attrs |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
        })

        Tool.ok(
          "#{updated.name} updated: #{attrs |> Map.keys() |> Enum.map_join(", ", &to_string/1)}.",
          %{
            "name" => updated.name,
            "group" => updated.group,
            "label_template" => updated.label_template,
            "lock_behavior" => updated.lock_behavior,
            "paused" => updated.paused,
            "timer" => updated.timer,
            "parameters" => updated.parameters,
            "environment_variables" => updated.environment_variables
          }
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Changeset.message(changeset)}
    end
  end

  # Only the keys the caller sent: a setting nobody named stays as it is, and
  # `paused` cannot be told apart from "absent" any other way.
  defp settings(args) do
    with {:ok, paused} <- optional_boolean(args, "paused"),
         {:ok, group} <- Args.optional(args, "group"),
         {:ok, label_template} <- Args.optional(args, "label_template"),
         {:ok, lock_behavior} <- Args.optional(args, "lock_behavior"),
         {:ok, timer} <- Args.optional(args, "timer"),
         {:ok, parameters} <- Args.object(args, "parameters"),
         {:ok, environment_variables} <- Args.object(args, "environment_variables") do
      attrs =
        %{}
        |> put_present(:group, group)
        |> put_present(:label_template, label_template)
        |> put_present(:lock_behavior, lock_behavior)
        |> put_present(:timer, timer)
        |> put_present(:paused, paused)
        |> put_present(
          :parameters,
          if(Map.has_key?(args, "parameters"), do: parameters, else: nil)
        )
        |> put_present(
          :environment_variables,
          if(Map.has_key?(args, "environment_variables"), do: environment_variables, else: nil)
        )

      {:ok, attrs}
    end
  end

  defp optional_boolean(args, key) do
    if Map.has_key?(args, key), do: Args.boolean(args, key), else: {:ok, nil}
  end

  defp put_present(attrs, _key, nil), do: attrs
  defp put_present(attrs, key, value), do: Map.put(attrs, key, value)

  # ── delete ─────────────────────────────────────────────────────────

  defp delete(args, ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, confirm} <- Args.boolean(args, "confirm"),
         :ok <- Auth.require_admin(ctx.user, "delete a pipeline") do
      case Pipelines.get_pipeline_by_name(name) do
        nil -> {:error, "Pipeline '#{name}' not found."}
        pipeline -> delete_pipeline(pipeline, confirm, ctx)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp delete_pipeline(pipeline, false, _ctx) do
    {:error,
     "Deleting #{pipeline.name} deletes the pipeline, its configuration and its run history. " <>
       "Call again with `confirm: true` to delete it."}
  end

  defp delete_pipeline(pipeline, true, ctx) do
    case Pipelines.delete_pipeline(pipeline) do
      {:ok, deleted} ->
        Events.config_changed(ctx.user.username, deleted.name, %{action: "deleted"})
        Tool.ok("#{deleted.name} deleted, with its run history.", %{"deleted" => true})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Changeset.message(changeset)}
    end
  end

  # ── the definition ─────────────────────────────────────────────────

  defp definition_arg(args) do
    case args["definition"] do
      definition when is_map(definition) ->
        validate(definition)

      _missing ->
        {:error, "`definition` is required: an object with at least a `name` and `stages`."}
    end
  end

  defp validate(definition) do
    with {:ok, name} <- text(definition["name"], "pipeline name"),
         {:ok, stages} <- stages(definition["stages"]),
         {:ok, materials} <- materials(definition["materials"] || []) do
      {:ok,
       %{
         name: name,
         group: definition["group"] || "defaultGroup",
         label_template: definition["label_template"] || "${COUNT}",
         lock_behavior: definition["lock_behavior"] || "none",
         timer: definition["timer"],
         parameters: string_map(definition["parameters"]),
         environment_variables: string_map(definition["environment_variables"]),
         materials: materials,
         stages: stages
       }}
    end
  end

  defp stages(stages) when is_list(stages) and stages != [], do: collect(stages, &stage/1)
  defp stages(_other), do: {:error, "`stages` must be a non-empty list."}

  defp stage(stage) when is_map(stage) do
    with {:ok, name} <- text(stage["name"], "stage name"),
         {:ok, approval_type} <- approval_type(stage["approval_type"]),
         {:ok, jobs} <- jobs(stage["jobs"]) do
      {:ok, %{name: name, approval_type: approval_type, jobs: jobs}}
    end
  end

  defp stage(_other), do: {:error, "Every stage must be an object."}

  defp approval_type(nil), do: {:ok, "success"}
  defp approval_type("success"), do: {:ok, "success"}
  defp approval_type("manual"), do: {:ok, "manual"}

  defp approval_type(other),
    do:
      {:error, "A stage's `approval_type` must be `success` or `manual`, not #{inspect(other)}."}

  defp jobs(jobs) when is_list(jobs) and jobs != [], do: collect(jobs, &job/1)
  defp jobs(_other), do: {:error, "Every stage needs at least one job."}

  defp job(job) when is_map(job) do
    with {:ok, name} <- text(job["name"], "job name"),
         {:ok, tasks} <- tasks(job["tasks"]) do
      {:ok, %{name: name, resources: string_list(job["resources"]), tasks: tasks}}
    end
  end

  defp job(_other), do: {:error, "Every job must be an object."}

  defp tasks(tasks) when is_list(tasks) and tasks != [], do: collect(tasks, &task/1)

  defp tasks(_other) do
    {:error,
     "A job needs at least one task: a job with nothing to do is a job that always passes."}
  end

  defp task(task) when is_map(task) do
    type = task["type"] || "exec"

    with {:ok, command} <- command(type, task["command"]) do
      {:ok,
       %{
         type: type,
         command: command,
         arguments: string_list(task["arguments"]),
         working_directory: task["working_directory"],
         run_if: task["run_if"] || "passed"
       }}
    end
  end

  defp task(_other), do: {:error, "Every task must be an object."}

  defp command("exec", command), do: text(command, "task command")
  defp command(_type, command), do: {:ok, command}

  defp materials(materials) when is_list(materials), do: collect(materials, &material/1)
  defp materials(_other), do: {:error, "`materials` must be a list."}

  defp material(material) when is_map(material) do
    with {:ok, url} <- text(material["url"], "material url") do
      {:ok,
       %{
         "type" => material["type"] || "git",
         "url" => url,
         "branch" => material["branch"],
         "destination" => material["destination"]
       }}
    end
  end

  defp material(_other), do: {:error, "Every material must be an object."}

  # A map is not a contract: a client can send anything, so each element is
  # checked before the first insert happens, and the first failure names itself.
  defp collect(values, fun) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, checked} -> {:cont, {:ok, [checked | acc]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, checked} -> {:ok, Enum.reverse(checked)}
      {:error, message} -> {:error, message}
    end
  end

  defp text(value, what) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "A #{what} is required."}
      trimmed -> {:ok, trimmed}
    end
  end

  defp text(_value, what), do: {:error, "A #{what} is required."}

  defp string_list(nil), do: []
  defp string_list(value) when is_binary(value), do: [value]
  defp string_list(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp string_list(_other), do: []

  defp string_map(nil), do: %{}

  defp string_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp string_map(_other), do: %{}
end
