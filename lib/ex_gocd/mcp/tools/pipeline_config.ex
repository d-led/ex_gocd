defmodule ExGoCD.Mcp.Tools.PipelineConfig do
  @moduledoc """
  Authoring: a graph of pipelines, built from a description.

  A pipeline is not a line of stages. GoCD's vocabulary is a graph — *fan-out* is
  one build and several deployments; *fan-in* is several upstreams and one
  deploy that waits for all of them; *passing results* is an artifact a job
  publishes and a `fetch` task elsewhere takes; and *build once* is what those
  two make possible, the artifact built once and every environment promoting
  that same build rather than rebuilding something nobody tested.

  So the shape here is a list of pipelines, not one. They are created in two
  passes, the way `ConfigXml` imports a document: every pipeline first, then the
  dependency materials, because a material may name a pipeline declared later in
  the same graph. It is one transaction — a typo in the third pipeline creates
  nothing — and a cycle is refused before anything is written, because that is
  the one mistake a graph can never recover from at run time.

  Deliberately not here: rewriting an existing pipeline's stages. A stage's job
  instances are keyed to the stage row, so replacing a stage is a migration
  rather than an edit; `gocd_update_pipeline` changes the pipeline's own
  settings and says so.
  """

  alias ExGoCD.{AuditLog.Events, ConfigAudit, PipelineGraph, Pipelines, Repo}
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
              "description" =>
                "The repository url, or — for a `dependency` — the upstream pipeline."
            },
            "pipeline" => %{
              "type" => "string",
              "description" =>
                "The upstream pipeline of a `dependency`. It may be another pipeline in " <>
                  "the same call, which is what makes a graph."
            },
            "stage" => %{
              "type" => "string",
              "description" =>
                "The upstream stage whose passing starts this pipeline. With several " <>
                  "dependencies this is fan-in: this pipeline waits for all of them."
            },
            "branch" => %{"type" => "string"},
            "destination" => %{"type" => "string"},
            "include" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" =>
                "Only changes under these paths trigger the pipeline. Note that a " <>
                  "material filter stops fan-in resolution working in GoCD, so a filter " <>
                  "on a shared repository means a fan-in target may never trigger."
            },
            "exclude" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Changes under these paths do not trigger the pipeline."
            }
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
            "clean_working_directory" => %{
              "type" => "boolean",
              "default" => false,
              "description" =>
                "Start from an empty working directory. A stage that only unpacks what " <>
                  "it fetched wants this; a stage that reuses a build does not."
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
                  "artifacts" => %{
                    "type" => "array",
                    "description" =>
                      "What this job publishes, for another pipeline to fetch instead " <>
                        "of building it again. The build-once half of a graph.",
                    "items" => %{
                      "type" => "object",
                      "properties" => %{
                        "type" => %{
                          "type" => "string",
                          "enum" => ["build", "test"],
                          "description" => "`test` artifacts are test reports."
                        },
                        "src" => %{
                          "type" => "string",
                          "description" => "A path or glob under the job's working directory."
                        },
                        "dest" => %{
                          "type" => "string",
                          "description" => "Where it is published."
                        }
                      },
                      "required" => ["src"]
                    }
                  },
                  "tasks" => %{
                    "type" => "array",
                    "items" => %{
                      "type" => "object",
                      "properties" => %{
                        "type" => %{
                          "type" => "string",
                          "enum" => ["exec", "fetch"],
                          "description" => "Default `exec`."
                        },
                        "command" => %{"type" => "string"},
                        "arguments" => %{"type" => "array", "items" => %{"type" => "string"}},
                        "working_directory" => %{"type" => "string"},
                        "run_if" => %{
                          "type" => "string",
                          "enum" => ["passed", "failed", "any"],
                          "description" => "Default `passed`."
                        },
                        "pipeline" => %{
                          "type" => "string",
                          "description" =>
                            "For a `fetch`: the pipeline whose artifact to take. It has " <>
                              "to be this pipeline or one it depends on."
                        },
                        "stage" => %{
                          "type" => "string",
                          "description" => "For a `fetch`: the stage."
                        },
                        "job" => %{"type" => "string", "description" => "For a `fetch`: the job."},
                        "src" => %{
                          "type" => "string",
                          "description" => "For a `fetch`: the artifact path to take."
                        },
                        "dest" => %{
                          "type" => "string",
                          "description" => "For a `fetch`: where to put it, here."
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
      "title" => "Create a pipeline, or a graph of them",
      "description" =>
        "Creates one pipeline from `definition`, or a whole graph from `pipelines` — the " <>
          "shapes worth having are fan-out (one build, several deployments), fan-in (a " <>
          "deploy that waits for QA, UAT and performance), and build once (a job " <>
          "publishes an artifact, the deploy pipelines `fetch` that same build instead " <>
          "of rebuilding it). Dependencies may name pipelines in the same call, in any " <>
          "order. Everything happens in one transaction: a definition wrong in the third " <>
          "pipeline creates nothing, and a cycle is refused before anything is written. " <>
          "Each answer ends with whether anything can actually run it. An " <>
          "administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "definition" => @definition,
          "pipelines" => %{
            "type" => "array",
            "description" =>
              "A graph: several pipelines in one call, in any order. A `dependency` " <>
                "material may name another pipeline here.",
            "items" => @definition
          }
        }
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

  @doc """
  Reads a graph exactly as `gocd_create_pipeline` reads it — one pipeline through
  `definition`, several through `pipelines` — and writes nothing.
  """
  @spec preview_graph(map()) :: {:ok, [map()]} | {:error, String.t()}
  def preview_graph(attributes) when is_map(attributes), do: definitions_arg(attributes)

  def preview_graph(_other), do: {:error, "A graph description must be an object."}

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
    with {:ok, definitions} <- definitions_arg(args),
         :ok <- Auth.require_admin(ctx.user, "create a pipeline"),
         :ok <- names_are_free(definitions),
         :ok <- graph_is_possible(definitions) do
      insert(definitions, ctx)
    else
      {:error, message} -> {:error, message}
    end
  end

  defp names_are_free(definitions) do
    Enum.find_value(definitions, :ok, fn definition ->
      case Pipelines.get_pipeline_by_name(definition.name) do
        nil ->
          nil

        _pipeline ->
          {:error,
           "Pipeline '#{definition.name}' already exists. `gocd_update_pipeline` changes " <>
             "its settings, `gocd_describe_pipeline` shows what it is made of."}
      end
    end)
  end

  # The mistakes a graph cannot recover from at run time. A dangling fetch is a
  # warning instead: GoCD keeps a configuration it can only fail, and so does this.
  defp graph_is_possible(definitions) do
    case Enum.filter(PipelineGraph.problems(definitions), &fatal?/1) do
      [] -> :ok
      [problem | _] -> {:error, problem.message}
    end
  end

  defp fatal?(%{code: code}), do: code in [:duplicate_pipeline, :unknown_upstream, :cycle]

  # One transaction for the whole graph, and two passes through it: every
  # pipeline and its stages first, then the materials — because a dependency may
  # name a pipeline declared later in the same graph. A stage that fails its
  # changeset rolls all of it back, so a typo leaves nothing behind.
  defp insert(definitions, ctx) do
    result =
      Repo.transaction(fn ->
        definitions
        |> Enum.map(&create_pipeline/1)
        |> attach_materials()
      end)

    case result do
      {:ok, built} -> created(built, ctx)
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Changeset.message(changeset)}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, "Could not create the graph: #{inspect(reason)}"}
    end
  end

  defp create_pipeline(definition) do
    with {:ok, pipeline} <- insert_pipeline(definition),
         {:ok, stages} <- add_stages(pipeline, definition.stages) do
      %{definition: definition, pipeline: pipeline, stages: stages, materials: []}
    else
      {:error, message} -> Repo.rollback(message)
    end
  end

  defp insert_pipeline(definition) do
    case Pipelines.create_pipeline(pipeline_attrs(definition)) do
      {:ok, pipeline} ->
        {:ok, pipeline}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Pipeline '#{definition.name}': #{Changeset.message(changeset)}"}
    end
  end

  defp attach_materials(built) do
    Enum.map(built, fn %{definition: definition, pipeline: pipeline} = entry ->
      materials = Enum.map(definition.materials, &attach_material(pipeline, &1))
      %{entry | materials: materials}
    end)
  end

  defp attach_material(pipeline, material) do
    case Pipelines.create_material_for_pipeline(pipeline, material) do
      {:ok, created} -> created
      {:error, reason} -> Repo.rollback(material_error(material, reason))
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
    attrs = %{
      name: stage.name,
      pipeline_id: pipeline.id,
      approval_type: stage.approval_type,
      clean_working_directory: stage.clean_working_directory
    }

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
    attrs = %{
      name: job.name,
      stage_id: stage.id,
      resources: job.resources,
      artifact_configs: artifact_configs(job.artifacts)
    }

    case Pipelines.create_job(attrs) do
      {:ok, created} ->
        with {:ok, tasks} <- add_tasks(created, job.tasks) do
          {:ok, %{name: created.name, tasks: tasks}}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Job '#{job.name}' of stage '#{stage.name}': #{Changeset.message(changeset)}"}
    end
  end

  # Jobs store their artifacts under "artifacts", the shape the scheduler reads
  # when it tells an agent what to upload. No artifacts is an empty map, not a
  # list with nothing in it, because that is what the XML writer and the
  # scheduler both check.
  defp artifact_configs([]), do: %{}
  defp artifact_configs(artifacts), do: %{"artifacts" => artifacts}

  defp add_tasks(job, tasks) do
    tasks
    |> Enum.reduce_while({:ok, []}, fn task, {:ok, acc} ->
      case Pipelines.create_task(Map.put(task_attrs(task), :job_id, job.id)) do
        {:ok, created} ->
          {:cont, {:ok, [task_label(created) | acc]}}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:halt, {:error, "Task of job '#{job.name}': #{Changeset.message(changeset)}"}}
      end
    end)
    |> in_order()
  end

  # A fetch task has no command: where to take the artifact from is its whole
  # content, and it lives in `arguments` in the order the scheduler reads it.
  defp task_attrs(%{type: "fetch"} = task) do
    %{
      type: "fetch",
      arguments: [task.pipeline, task.stage, task.job, task.src, task.dest],
      run_if: task.run_if
    }
  end

  defp task_attrs(task) do
    %{
      type: task.type,
      command: task.command,
      arguments: task.arguments,
      working_directory: task.working_directory,
      run_if: task.run_if
    }
  end

  defp in_order({:ok, built}), do: {:ok, Enum.reverse(built)}
  defp in_order({:error, message}), do: {:error, message}

  defp task_label(%{type: "fetch", arguments: [pipeline, stage, job | _]}),
    do: "fetch #{pipeline}/#{stage}/#{job}"

  defp task_label(task) do
    [task.command | task.arguments || []] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end

  defp created([%{pipeline: pipeline, materials: materials, stages: stages} = built], ctx) do
    audit_creation(built, ctx)
    jobs = stages |> Enum.flat_map(& &1.jobs) |> length()
    fit = ConfigAudit.fit_pipeline(pipeline.name)
    answer = pipeline_answer(built, ctx, fit)

    Tool.ok(
      "#{pipeline.name} created in group #{Render.cell(pipeline.group)}: " <>
        "#{length(stages)} stage(s), #{jobs} job(s), #{length(materials)} material(s).\n" <>
        "Its configuration: #{answer["link"]}\n" <>
        "It has not run yet; `gocd_trigger_pipeline` starts it." <>
        verdict_text(fit),
      answer
    )
  end

  # A graph is created as a graph and reported as one: the edges are what was
  # asked for, and naming the shapes (fan-out, fan-in) is what makes the answer
  # checkable by the person who described it.
  defp created(built, ctx) do
    Enum.each(built, &audit_creation(&1, ctx))

    edges = edges(built)

    answers =
      Enum.map(built, fn %{pipeline: pipeline} = entry ->
        pipeline_answer(entry, ctx, ConfigAudit.fit_pipeline(pipeline.name))
      end)

    Tool.ok(
      graph_text(answers, edges),
      %{
        "pipelines" => answers,
        "edges" => Enum.map(edges, fn {from, to} -> %{"from" => from, "to" => to} end)
      }
    )
  end

  defp audit_creation(%{pipeline: pipeline, materials: materials, stages: stages}, ctx) do
    Events.config_changed(ctx.user.username, pipeline.name, %{
      action: "created",
      stages: Enum.map(stages, & &1.name),
      materials: Enum.map(materials, & &1.url)
    })
  end

  defp pipeline_answer(%{pipeline: pipeline, materials: materials, stages: stages}, ctx, fit) do
    %{
      "name" => pipeline.name,
      "group" => pipeline.group,
      "link" => "#{ctx.base_url}/admin/pipelines/#{pipeline.name}/edit",
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
  end

  # `build -> test-a, test-b`: the dependency materials as edges, upstream first.
  defp edges(built) do
    for %{pipeline: pipeline, materials: materials} <- built,
        material <- materials,
        material.type == "dependency",
        do: {upstream_name(material), pipeline.name}
  end

  defp upstream_name(material) do
    (material.type_specific_config || %{})["pipeline_name"] || material.url
  end

  defp graph_text(answers, edges) do
    [
      "#{length(answers)} pipelines created: #{Enum.map_join(answers, ", ", &"`#{&1["name"]}`")}.",
      edge_text(edges),
      shape_text(edges),
      verdict_text_for(answers),
      "Edit pages: #{Enum.map_join(answers, ", ", & &1["link"])}",
      "They have not run yet; `gocd_trigger_pipeline` starts the first one."
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp edge_text(edges) do
    edges
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map_join("\n", fn {upstream, downstreams} ->
      "  `#{upstream}` -> #{Enum.map_join(downstreams, ", ", &"`#{&1}`")}"
    end)
  end

  # The shapes are worth naming back: they are the reason the graph was asked
  # for, and a person recognises fan-in faster than they read three edges.
  defp shape_text(edges) do
    fan_out =
      edges
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.filter(fn {_upstream, downstreams} -> length(downstreams) > 1 end)
      |> Enum.map(fn {upstream, downstreams} ->
        "fan-out from `#{upstream}` to #{length(downstreams)} pipelines"
      end)

    fan_in =
      edges
      |> Enum.group_by(&elem(&1, 1))
      |> Enum.filter(fn {_downstream, upstreams} -> length(upstreams) > 1 end)
      |> Enum.map(fn {downstream, upstreams} ->
        "fan-in at `#{downstream}` from #{length(upstreams)}"
      end)

    case fan_out ++ fan_in do
      [] -> ""
      shapes -> "Shapes: " <> Enum.join(shapes, "; ") <> "."
    end
  end

  defp verdict_text_for(answers) do
    stuck =
      for answer <- answers,
          will_run = answer["will_run"],
          is_map(will_run),
          problem = will_run["first_problem"],
          do: "`#{answer["name"]}` #{problem}"

    case stuck do
      [] ->
        "Will it run? Yes — every job in every pipeline has an agent."

      [first | _] ->
        "Will it run? Not yet — #{first}. `gocd_audit_config` shows the rest."
    end
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
          advice_phrase(stuck.advice) <> "`gocd_audit_config` shows the rest."
    end
  end

  defp advice_phrase(nil), do: ""
  defp advice_phrase(advice), do: advice <> " "

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

  defp definitions_arg(args) do
    case {args["definition"], args["pipelines"]} do
      {nil, nil} ->
        {:error, "Give `definition` for one pipeline, or `pipelines` for a graph of them."}

      {nil, definitions} when is_list(definitions) ->
        graph(definitions)

      {nil, other} ->
        {:error, "`pipelines` must be a list of definitions, not #{inspect(other)}."}

      {definition, nil} when is_map(definition) ->
        with {:ok, validated} <- validate(definition), do: {:ok, [validated]}

      {other, nil} ->
        {:error, "`definition` must be an object, not #{inspect(other)}."}

      {_definition, _pipelines} ->
        {:error, "Give one of `definition` and `pipelines`, not both."}
    end
  end

  defp graph([]), do: {:error, "`pipelines` is empty: a graph needs at least one pipeline."}

  defp graph(definitions) do
    definitions
    |> Enum.reduce_while({:ok, []}, fn definition, {:ok, acc} ->
      if is_map(definition) do
        case validate(definition) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          {:error, message} -> {:halt, {:error, message}}
        end
      else
        {:halt,
         {:error, "Every pipeline in `pipelines` must be an object, not #{inspect(definition)}."}}
      end
    end)
    |> in_order()
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
         {:ok, clean} <- setting(stage["clean_working_directory"], "clean_working_directory"),
         {:ok, jobs} <- jobs(stage["jobs"]) do
      {:ok,
       %{
         name: name,
         approval_type: approval_type,
         clean_working_directory: clean || false,
         jobs: jobs
       }}
    end
  end

  defp stage(_other), do: {:error, "Every stage must be an object."}

  defp setting(nil, _name), do: {:ok, nil}
  defp setting(value, _name) when is_boolean(value), do: {:ok, value}

  defp setting(other, name),
    do: {:error, "`#{name}` must be true or false, not #{inspect(other)}."}

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
         {:ok, artifacts} <- artifacts(job["artifacts"] || []),
         {:ok, tasks} <- tasks(job["tasks"]) do
      {:ok,
       %{
         name: name,
         resources: string_list(job["resources"]),
         artifacts: artifacts,
         tasks: tasks
       }}
    end
  end

  defp job(_other), do: {:error, "Every job must be an object."}

  defp artifacts(artifacts) when is_list(artifacts), do: collect(artifacts, &artifact/1)

  defp artifact(artifact) when is_map(artifact) do
    with {:ok, src} <- text(artifact["src"], "artifact `src`") do
      {:ok,
       %{
         "type" => artifact["type"] || "build",
         "src" => src,
         "dest" => artifact["dest"] || ""
       }}
    end
  end

  defp artifact(_other), do: {:error, "Every artifact must be an object with a `src`."}

  defp tasks(tasks) when is_list(tasks) and tasks != [], do: collect(tasks, &task/1)

  defp tasks(_other) do
    {:error,
     "A job needs at least one task: a job with nothing to do is a job that always passes."}
  end

  defp task(task) when is_map(task) do
    case task["type"] || "exec" do
      "fetch" -> fetch_task(task)
      type -> exec_task(type, task)
    end
  end

  defp task(_other), do: {:error, "Every task must be an object."}

  defp fetch_task(task) do
    with {:ok, pipeline} <- text(task["pipeline"], "the pipeline a `fetch` task takes from"),
         {:ok, stage} <- text(task["stage"], "the stage a `fetch` task takes from"),
         {:ok, job} <- text(task["job"], "the job a `fetch` task takes from"),
         {:ok, src} <- text(task["src"], "the artifact a `fetch` task takes") do
      {:ok,
       %{
         type: "fetch",
         pipeline: pipeline,
         stage: stage,
         job: job,
         src: src,
         dest: task["dest"] || ".",
         run_if: task["run_if"] || "passed"
       }}
    end
  end

  defp exec_task(type, task) do
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

  defp command("exec", command), do: text(command, "task command")
  defp command(_type, command), do: {:ok, command}

  defp materials(materials) when is_list(materials), do: collect(materials, &material/1)
  defp materials(_other), do: {:error, "`materials` must be a list."}

  defp material(material) when is_map(material) do
    with {:ok, type} <- material_type(material["type"]),
         {:ok, url} <- material_url(type, material),
         :ok <- stage_allowed(type, material["stage"]) do
      {:ok,
       %{
         "type" => type,
         "url" => url,
         "branch" => material["branch"],
         "destination" => material["destination"],
         "filter_include" => string_list(material["include"]),
         "filter_ignore" => string_list(material["exclude"]),
         "stage_name" => material["stage"]
       }}
    end
  end

  defp material(_other), do: {:error, "Every material must be an object."}

  defp material_type(nil), do: {:ok, "git"}

  defp material_type(type) when type in ["git", "svn", "hg", "dependency"], do: {:ok, type}

  defp material_type(other) do
    {:error,
     "A material's `type` must be `git`, `svn`, `hg` or `dependency`, not #{inspect(other)}."}
  end

  # A dependency names its upstream with `pipeline`; `url` is the older spelling
  # of the same thing, and a repository material has only a url.
  defp material_url("dependency", material) do
    text(
      material["pipeline"] || material["url"],
      "the upstream pipeline of a dependency material"
    )
  end

  defp material_url(_type, material), do: text(material["url"], "material url")

  defp stage_allowed("dependency", _stage), do: :ok
  defp stage_allowed(_type, nil), do: :ok

  defp stage_allowed(_type, stage) do
    {:error,
     "Only a dependency material names an upstream `stage`; #{inspect(stage)} was given to " <>
       "another kind of material."}
  end

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
