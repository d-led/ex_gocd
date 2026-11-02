defmodule ExGoCD.Mcp.Tools.Pipelines do
  @moduledoc """
  Pipelines, read: what is configured, what ran, what one run contained, and
  what changed between two of them.

  Two of these tools look similar and answer different questions.
  `gocd_list_pipelines` describes *configurations* — stages, jobs, materials —
  and `gocd_dashboard` (in `Tools.Server`) describes the *latest run* of each.
  A pipeline that has never run appears in the first and is `NeverRun` in the
  second.

  Acting on a pipeline is a different family: `Tools.PipelineOperations`.
  """

  alias ExGoCD.{Environments, Pipelines}
  alias ExGoCD.Mcp.{Args, PipelineView, Render, Tool}
  alias ExGoCD.Pipelines.{Material, Pipeline, Stage, Task}

  @names ~w(gocd_list_pipelines gocd_describe_pipeline gocd_pipeline_status gocd_pipeline_history
            gocd_pipeline_instance gocd_pipeline_config_diff gocd_compare_pipeline_instances)

  @tools [
    %{
      "name" => "gocd_list_pipelines",
      "title" => "List pipeline configurations",
      "description" =>
        "Every pipeline configured on this server, with its group, its stages in order, how " <>
          "many jobs and materials it has, and whether it is paused or locked. Filter by " <>
          "`group`, by words in the name, or by `paused`. This lists configurations; for the " <>
          "latest run of each, use `gocd_dashboard`.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Words the pipeline name must contain."
          },
          "group" => %{"type" => "string", "description" => "Only this pipeline group."},
          "paused" => %{
            "type" => "boolean",
            "description" => "Only paused (`true`) or only running (`false`) pipelines."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200, "default" => 50},
          "offset" => %{"type" => "integer", "minimum" => 0, "default" => 0}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_describe_pipeline",
      "title" => "Describe one pipeline's configuration",
      "description" =>
        "Everything a pipeline is made of: its group, whether it is paused and why, its " <>
          "materials, its stages and their jobs (with each job's tasks, resources, timeout " <>
          "and environment variables), its parameters, and the environment it belongs to. " <>
          "Secure variables are named but never shown. If the pipeline is defined by a " <>
          "config repository, that is said instead of pretending it is edited here.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."}
        },
        "required" => ["name"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_pipeline_status",
      "title" => "Is this pipeline runnable, and how did it last go",
      "description" =>
        "Paused? Locked? Schedulable? — and the latest run with its stages. The answer the " <>
          "pipeline status API gives, which is the one to check before triggering it: a " <>
          "paused or locked pipeline refuses a trigger.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."}
        },
        "required" => ["name"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_pipeline_history",
      "title" => "List a pipeline's runs",
      "description" =>
        "A pipeline's runs, newest first, each with its counter, label, when it was " <>
          "scheduled, its status and how each stage ended. Page with `limit` and `offset`; " <>
          "the total is reported so a caller knows how much there is.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100, "default" => 10},
          "offset" => %{"type" => "integer", "minimum" => 0, "default" => 0}
        },
        "required" => ["name"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_pipeline_instance",
      "title" => "One pipeline run in full",
      "description" =>
        "One run of a pipeline: its label, what triggered it, its status, and every stage " <>
          "with its state, result and jobs. This is the run page, as data.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          }
        },
        "required" => ["name", "counter"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_pipeline_config_diff",
      "title" => "What changed in the config since the previous run",
      "description" =>
        "The configuration diff between a run and the run before it, as the run's " <>
          "`config_diff` page shows it. `No configuration change` is a real answer: it " <>
          "means the two runs saw the same configuration.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          }
        },
        "required" => ["name", "counter"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_compare_pipeline_instances",
      "title" => "Compare two runs of a pipeline",
      "description" =>
        "What differs between two runs: each material's revision in both, the modifications " <>
          "in between, the environment variables each run used, and whether the configuration " <>
          "itself changed. Use counter `0` for \"before the first run\".",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "from" => %{
            "type" => "integer",
            "minimum" => 0,
            "description" => "The earlier counter, or 0."
          },
          "to" => %{"type" => "integer", "minimum" => 1, "description" => "The later counter."}
        },
        "required" => ["name", "from", "to"]
      },
      "annotations" => Tool.read_only()
    }
  ]

  @doc "The definitions of this family's tools."
  @spec definitions() :: [map()]
  def definitions, do: @tools

  @doc "The names of this family's tools."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Whether this family answers to a tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: name in @names

  @doc "Calls one of this family's tools."
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call("gocd_list_pipelines", args, ctx), do: list(args, ctx)
  def call("gocd_describe_pipeline", args, ctx), do: describe(args, ctx)
  def call("gocd_pipeline_status", args, ctx), do: status(args, ctx)
  def call("gocd_pipeline_history", args, ctx), do: history(args, ctx)
  def call("gocd_pipeline_instance", args, ctx), do: instance(args, ctx)
  def call("gocd_pipeline_config_diff", args, ctx), do: config_diff(args, ctx)
  def call("gocd_compare_pipeline_instances", args, ctx), do: compare(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp list(args, _ctx) do
    with {:ok, query} <- Args.optional(args, "query"),
         {:ok, group} <- Args.optional(args, "group"),
         {:ok, paused} <- Args.boolean(args, "paused"),
         {:ok, limit} <- Args.integer(args, "limit", default: 50, min: 1, max: 200),
         {:ok, offset} <- Args.integer(args, "offset", default: 0, min: 0, max: 100_000) do
      matching =
        Pipelines.list_pipelines()
        |> Enum.filter(&matches?(&1, query, group, args, paused))
        |> Enum.sort_by(& &1.name)

      shown = Enum.slice(matching, offset, limit)

      text =
        "#{length(matching)} pipeline(s)" <>
          if(group, do: " in group `#{group}`", else: "") <>
          ", showing #{length(shown)} from #{offset}\n\n" <>
          Render.table(
            ["PIPELINE", "GROUP", "STAGES", "JOBS", "MATERIALS", "PAUSED", "LOCKED"],
            Enum.map(shown, fn pipeline -> row(pipeline) end)
          )

      Tool.ok(text, %{
        "matched" => length(matching),
        "offset" => offset,
        "limit" => limit,
        "pipelines" => Enum.map(shown, &summary/1)
      })
    end
  end

  defp describe(args, _ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         %Pipeline{} = pipeline <- Pipelines.get_pipeline_by_name(name) do
      pipeline = Pipelines.resolve_template_stages(pipeline)

      stages =
        pipeline.stages
        |> Enum.sort_by(& &1.id)
        |> Enum.map(&stage_map/1)

      structured = %{
        "name" => pipeline.name,
        "group" => pipeline.group,
        "paused" => pipeline.paused,
        "paused_by" => pipeline.paused_by,
        "pause_cause" => pipeline.pause_cause,
        "locked" => pipeline.locked,
        "label_template" => pipeline.label_template,
        "timer" => pipeline.timer,
        "template" => pipeline.template_name || template_name(pipeline),
        "config_repo_id" => pipeline.config_repo_id,
        "environment" => environment_name(pipeline.name),
        "parameters" => pipeline.parameters || %{},
        "environment_variables" =>
          env_pairs(pipeline.environment_variables, pipeline.secure_variables),
        "materials" => Enum.map(pipeline.materials || [], &material_map/1),
        "stages" => stages
      }

      Tool.ok(describe_text(structured), structured)
    else
      nil -> not_found(args)
      {:error, message} -> {:error, message}
    end
  end

  defp status(args, _ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         %Pipeline{} = pipeline <- Pipelines.get_pipeline_by_name(name) do
      locked = Pipelines.pipeline_locked?(pipeline)
      latest = Pipelines.list_pipeline_instances(pipeline.id, limit: 1) |> List.first()

      structured = %{
        "name" => pipeline.name,
        "paused" => pipeline.paused,
        "paused_by" => pipeline.paused_by,
        "paused_cause" => pipeline.pause_cause,
        "paused_at" => Render.timestamp(pipeline.paused_at),
        "locked" => locked,
        "schedulable" => not pipeline.paused and not locked,
        "latest_instance" => latest && PipelineView.instance(latest)
      }

      text =
        [
          "#{pipeline.name}: " <>
            if(pipeline.paused, do: "paused", else: "not paused") <>
            " · " <>
            if(locked, do: "locked", else: "not locked") <>
            " · " <>
            if(pipeline.paused or locked, do: "not schedulable", else: "schedulable"),
          if(pipeline.paused,
            do:
              "Paused by #{Render.cell(pipeline.paused_by)} at #{Render.timestamp(pipeline.paused_at)}: #{Render.cell(pipeline.pause_cause)}",
            else: nil
          ),
          latest_text(latest)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      Tool.ok(text, structured)
    else
      nil -> not_found(args)
      {:error, message} -> {:error, message}
    end
  end

  defp history(args, _ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, limit} <- Args.integer(args, "limit", default: 10, min: 1, max: 100),
         {:ok, offset} <- Args.integer(args, "offset", default: 0, min: 0, max: 100_000),
         %Pipeline{} = pipeline <- Pipelines.get_pipeline_by_name(name) do
      instances = Pipelines.list_pipeline_instances(pipeline.id, offset: offset, limit: limit)
      total = Pipelines.count_pipeline_instances(pipeline.id)

      text =
        "#{name}: #{total} run(s), showing #{length(instances)} from #{offset}\n\n" <>
          Render.table(
            ["RUN", "LABEL", "SCHEDULED", "STATUS", "STAGES", "TRIGGER"],
            Enum.map(instances, fn instance ->
              [
                instance.counter,
                instance.label,
                Render.timestamp(instance.inserted_at),
                Pipelines.pipeline_instance_status(instance),
                Enum.map_join(instance.stage_instances || [], " → ", &stage_summary/1),
                get_in(instance.build_cause || %{}, ["triggerMessage"])
              ]
            end)
          )

      Tool.ok(text, %{
        "name" => name,
        "total" => total,
        "offset" => offset,
        "instances" => Enum.map(instances, &PipelineView.instance/1)
      })
    else
      nil -> not_found(args)
      {:error, message} -> {:error, message}
    end
  end

  defp instance(args, _ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, counter} <- Args.required_integer(args, "counter"),
         instance when not is_nil(instance) <- Pipelines.get_pipeline_instance(name, counter) do
      structured = PipelineView.instance(instance)

      text =
        [
          "#{name} ##{counter}" <>
            if(instance.label, do: " (#{instance.label})", else: ""),
          "Status: #{structured["status"]} · scheduled #{structured["scheduled_at"]}",
          "Trigger: #{Render.cell(structured["trigger"])}" <>
            if(structured["comment"], do: "\nComment: #{structured["comment"]}", else: ""),
          "",
          PipelineView.stage_table(instance.stage_instances || [])
        ]
        |> Enum.join("\n")

      Tool.ok(text, structured)
    else
      nil -> {:error, instance_not_found(args)}
      {:error, message} -> {:error, message}
    end
  end

  defp config_diff(args, _ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, counter} <- Args.required_integer(args, "counter") do
      case Pipelines.config_diff(name, counter) do
        {:ok, nil} ->
          Tool.ok(
            "No configuration change between #{name} ##{counter} and the run before it.",
            %{"name" => name, "counter" => counter, "changed" => false}
          )

        {:ok, diff} ->
          Tool.ok(
            "The configuration changed between #{name} ##{counter} and the run before it:\n\n" <>
              Render.truncate(inspect(diff, pretty: true, limit: :infinity), 4_000),
            %{"name" => name, "counter" => counter, "changed" => true, "diff" => diff}
          )

        {:error, :instance_not_found} ->
          {:error, instance_not_found(args)}
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp compare(args, _ctx) do
    case Args.all(args, name: :string, from: :integer, to: :integer) do
      {:ok, request} -> compare_runs(request)
      {:error, message} -> {:error, message}
    end
  end

  defp compare_runs(request) do
    comparison = Pipelines.compare_instances(request.name, request.from, request.to)
    structured = comparison_map(comparison)

    Tool.ok(compare_text(request, structured), structured)
  end

  defp compare_text(request, structured) do
    [
      "#{request.name}: ##{from_text(request.from)} → ##{request.to}",
      config_change_note(structured["config_changed"]),
      "",
      Render.table(["MATERIAL", "FROM", "TO"], Enum.map(structured["materials"], &material_row/1))
    ]
    |> Enum.join("\n")
  end

  defp config_change_note(true), do: "The configuration changed between the two runs."

  defp config_change_note(_unchanged),
    do: "The configuration did not change between the two runs."

  defp material_row(material) do
    [
      material["url"] || material["type"],
      material["from_revision"],
      material["to_revision"]
    ]
  end

  # ── pipeline configuration rendering ───────────────────────────────

  defp matches?(pipeline, query, group, args, paused) do
    name_matches?(pipeline.name, query) and group_matches?(pipeline, group) and
      pause_matches?(pipeline, args, paused)
  end

  defp name_matches?(_name, nil), do: true

  defp name_matches?(name, query),
    do: String.contains?(String.downcase(name), String.downcase(query))

  defp group_matches?(_pipeline, nil), do: true

  defp group_matches?(pipeline, group),
    do: String.downcase(pipeline.group || "") == String.downcase(group)

  # `paused` is a filter only when the caller sent it; `Args.boolean/2` cannot
  # tell "absent" from "false", so the presence of the key decides.
  defp pause_matches?(pipeline, args, paused) do
    not Map.has_key?(args, "paused") or pipeline.paused == paused
  end

  defp row(pipeline) do
    [
      pipeline.name,
      pipeline.group,
      Enum.map_join(pipeline.stages || [], " → ", & &1.name),
      length(jobs_of(pipeline)),
      length(pipeline.materials || []),
      pipeline.paused,
      pipeline.locked
    ]
  end

  defp summary(pipeline) do
    %{
      "name" => pipeline.name,
      "group" => pipeline.group,
      "stages" => Enum.map(pipeline.stages || [], & &1.name),
      "jobs" => length(jobs_of(pipeline)),
      "materials" => Enum.map(pipeline.materials || [], &material_label/1),
      "paused" => pipeline.paused,
      "locked" => pipeline.locked,
      "config_repo_id" => pipeline.config_repo_id
    }
  end

  defp jobs_of(pipeline), do: Enum.flat_map(pipeline.stages || [], &(&1.jobs || []))

  defp stage_map(%Stage{} = stage) do
    %{
      "name" => stage.name,
      "approval_type" => stage.approval_type,
      "fetch_materials" => stage.fetch_materials,
      "clean_working_directory" => stage.clean_working_directory,
      "environment_variables" => env_pairs(stage.environment_variables, stage.secure_variables),
      "jobs" =>
        stage.jobs
        |> Enum.sort_by(& &1.id)
        |> Enum.map(fn job ->
          %{
            "name" => job.name,
            "resources" => job.resources || [],
            "timeout" => job.timeout,
            "run_instance_count" => job.run_instance_count,
            "elastic_profile_id" => job.elastic_profile_id,
            "environment_variables" => env_pairs(job.environment_variables, job.secure_variables),
            "tasks" => Enum.map(job.tasks || [], &task_label/1)
          }
        end)
    }
  end

  defp material_map(%Material{} = material) do
    %{
      "type" => material.type,
      "url" => material.url,
      "branch" => material.branch,
      "destination" => material.destination,
      "auto_update" => material.auto_update,
      "filter_include" => material.filter_include || [],
      "filter_ignore" => material.filter_ignore || []
    }
  end

  defp material_label(%Material{} = material) do
    branch = if material.branch, do: "@#{material.branch}", else: ""
    "#{material.type} #{material.url}#{branch}"
  end

  defp task_label(%Task{} = task) do
    arguments = Enum.join(task.arguments || [], " ")
    command = [task.command, arguments] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")

    [
      task.type && "#{task.type}: #{command}",
      task.working_directory && "in #{task.working_directory}",
      task.run_if && task.run_if != "passed" && "run if #{task.run_if}"
    ]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join(" ")
  end

  # A value may be a plain string or the API's `%{"value" => .., "secure" => ..}`
  # shape. A secure value is never shown: its name is the answer.
  defp env_pairs(environment_variables, secure_variables) do
    plain =
      (environment_variables || %{})
      |> Enum.reject(fn {_key, value} -> secure?(value) end)
      |> Enum.map(fn {key, value} -> {to_string(key), plain_value(value)} end)

    secure =
      (secure_variables || %{})
      |> Map.keys()
      |> Enum.map(&{to_string(&1), "(secure)"})

    (plain ++ secure) |> Enum.sort() |> Map.new()
  end

  defp secure?(%{"secure" => true}), do: true
  defp secure?(_value), do: false

  defp plain_value(%{"value" => value}), do: to_string(value)
  defp plain_value(value), do: value

  defp environment_name(pipeline_name) do
    case Environments.get_pipeline_environment(pipeline_name) do
      nil -> nil
      environment -> environment.name
    end
  end

  defp template_name(%Pipeline{template: %{name: name}}) when is_binary(name), do: name
  defp template_name(_pipeline), do: nil

  defp describe_text(structured) do
    header =
      [
        "#{structured["name"]} · group #{Render.cell(structured["group"])}" <>
          if(structured["environment"],
            do: " · environment #{structured["environment"]}",
            else: ""
          ),
        "Paused: #{Render.cell(structured["paused"])}" <>
          if(structured["paused"],
            do:
              " by #{Render.cell(structured["paused_by"])}: #{Render.cell(structured["pause_cause"])}",
            else: ""
          ) <>
          " · locked: #{Render.cell(structured["locked"])} · label `#{Render.cell(structured["label_template"])}`",
        if(structured["template"], do: "Uses template #{structured["template"]}.", else: nil),
        if(structured["config_repo_id"],
          do:
            "Defined by config repository ##{structured["config_repo_id"]}: it is not edited on this server.",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    materials =
      if structured["materials"] == [] do
        []
      else
        [
          "",
          "Materials:",
          Render.table(
            ["TYPE", "URL", "BRANCH", "DESTINATION"],
            Enum.map(structured["materials"], fn material ->
              [material["type"], material["url"], material["branch"], material["destination"]]
            end)
          )
        ]
      end

    parameters =
      if map_size(structured["parameters"]) == 0 do
        []
      else
        ["", "Parameters:", Render.bullets(kv_lines(structured["parameters"]))]
      end

    variables =
      if map_size(structured["environment_variables"]) == 0 do
        []
      else
        [
          "",
          "Environment variables:",
          Render.bullets(kv_lines(structured["environment_variables"]))
        ]
      end

    stages =
      Enum.flat_map(structured["stages"], fn stage ->
        [
          "",
          "Stage #{stage["name"]} (#{stage["approval_type"]})" <>
            if(stage["environment_variables"] != %{},
              do: " · #{map_size(stage["environment_variables"])} variable(s)",
              else: ""
            ),
          Render.table(
            ["JOB", "RESOURCES", "TIMEOUT", "TASKS"],
            Enum.map(stage["jobs"], fn job ->
              [job["name"], job["resources"], job["timeout"], Enum.join(job["tasks"], "; ")]
            end)
          )
        ]
      end)

    (header ++ materials ++ parameters ++ variables ++ stages) |> Enum.join("\n")
  end

  defp kv_lines(map), do: Enum.map(Enum.sort(map), fn {key, value} -> "#{key}=#{value}" end)

  # ── comparison ─────────────────────────────────────────────────────

  defp comparison_map(comparison) do
    %{
      "materials" => Enum.map(comparison.materials, &stringify/1),
      "from_environment_variables" => comparison.from_environment_variables,
      "to_environment_variables" => comparison.to_environment_variables,
      "config_changed" => comparison.config_changed
    }
  end

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp from_text(0), do: "before the first run"
  defp from_text(counter), do: counter

  defp stage_summary(stage) do
    "#{stage.name}:#{stage.result || stage.state || "NotRun"}"
  end

  defp latest_text(nil), do: "Latest: this pipeline has never run."

  defp latest_text(instance) do
    "Latest: #{PipelineView.instance_line(instance)}\n\n" <>
      PipelineView.stage_table(instance.stage_instances || [])
  end

  defp not_found(args) do
    {:error, "Pipeline '#{args["name"]}' not found."}
  end

  defp instance_not_found(args), do: "Run ##{args["counter"]} of '#{args["name"]}' not found."
end
