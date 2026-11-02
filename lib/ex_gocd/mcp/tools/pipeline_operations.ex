defmodule ExGoCD.Mcp.Tools.PipelineOperations do
  @moduledoc """
  Pipelines, acted on: trigger one, pause or unpause it, release its lock, and
  leave a comment on a run.

  Every one of these is permission-checked the way the pipeline operations API
  checks it, and every one that changes something writes the audit entry the web
  UI writes — so `gocd_audit_log` shows an assistant's action beside a person's,
  with the name of whoever the request authenticated as.

  `gocd_unlock_pipeline` asks for `confirm` because it is the one operation whose
  purpose is to overrule a guard the server put in place: the lock exists because
  the previous run failed.
  """

  alias ExGoCD.{AuditLog.Events, Pipelines}
  alias ExGoCD.Mcp.{Args, Auth, Tool}

  @names ~w(gocd_trigger_pipeline gocd_set_pipeline_paused gocd_unlock_pipeline
            gocd_comment_on_pipeline)

  @tools [
    %{
      "name" => "gocd_trigger_pipeline",
      "title" => "Trigger a pipeline run",
      "description" =>
        "Starts a run of a pipeline, as the trigger button does: it creates the run, schedules " <>
          "the first stage's jobs, and answers with the run's counter and a link. A paused or " <>
          "locked pipeline, one already being triggered, and a server in maintenance mode are " <>
          "refused with the reason — they are not errors to retry. `variables` are trigger-time " <>
          "values for variables the pipeline already declares; `materials` override a material's " <>
          "revision, and must name a fingerprint the pipeline actually has.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "variables" => %{
            "type" => "object",
            "description" => "Variable name to value, for variables the pipeline declares.",
            "additionalProperties" => %{"type" => "string"}
          },
          "materials" => %{
            "type" => "array",
            "description" => "Material revisions to run instead of the latest ones.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "fingerprint" => %{
                  "type" => "string",
                  "description" => "From `gocd_describe_pipeline`."
                },
                "revision" => %{"type" => "string", "description" => "The revision to run."}
              },
              "required" => ["fingerprint", "revision"]
            }
          }
        },
        "required" => ["name"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_set_pipeline_paused",
      "title" => "Pause or unpause a pipeline",
      "description" =>
        "Pauses a pipeline (with a cause, which the dashboard shows) or unpauses it. A paused " <>
          "pipeline refuses triggers; runs already in progress are not stopped.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "paused" => %{
            "type" => "boolean",
            "description" => "`true` to pause, `false` to unpause."
          },
          "cause" => %{
            "type" => "string",
            "description" => "Why it is paused. Shown on the dashboard."
          }
        },
        "required" => ["name", "paused"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_unlock_pipeline",
      "title" => "Release a pipeline's lock",
      "description" =>
        "Releases the lock a failed run put on a pipeline, so it can be triggered again. " <>
          "Reads the pipeline first: a pipeline that is not locked is answered as such and " <>
          "nothing changes. Releasing a lock lets a new run start while the failed one still " <>
          "needs attention, so it takes `confirm: true`.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "confirm" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "True releases the lock; false only reports what would change."
          }
        },
        "required" => ["name"]
      },
      "annotations" => Tool.destructive()
    },
    %{
      "name" => "gocd_comment_on_pipeline",
      "title" => "Comment on a run",
      "description" =>
        "Adds a comment to one run of a pipeline — the note the run page shows, kept in the " <>
          "run's build cause and recorded in the audit log under your name.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          },
          "comment" => %{"type" => "string", "description" => "The comment."}
        },
        "required" => ["name", "counter", "comment"]
      },
      "annotations" => Tool.writes()
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
  def call("gocd_trigger_pipeline", args, ctx), do: trigger(args, ctx)
  def call("gocd_set_pipeline_paused", args, ctx), do: set_paused(args, ctx)
  def call("gocd_unlock_pipeline", args, ctx), do: unlock(args, ctx)
  def call("gocd_comment_on_pipeline", args, ctx), do: comment(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp trigger(args, ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         :ok <- Auth.require_pipeline_access(ctx.user, "trigger a pipeline"),
         {:ok, variables} <- Args.object(args, "variables"),
         {:ok, overrides} <- Args.objects(args, "materials"),
         {:ok, overrides} <- known_materials(name, overrides) do
      options = %{
        "materials" => overrides,
        "environment_variables" => variables,
        "approver" => ctx.user.username
      }

      case Pipelines.trigger_pipeline(name, options) do
        {:ok, instance} ->
          Events.pipeline_triggered(ctx.user.username, name, instance.counter)

          link = "#{ctx.base_url}/pipelines/value_stream_map/#{name}/#{instance.counter}"

          Tool.ok(
            "#{name} ##{instance.counter} triggered. The first stage's jobs are queued; " <>
              "`gocd_queue` says whether an agent can take them.\n#{link}",
            %{"name" => name, "counter" => instance.counter, "link" => link}
          )

        {:error, reason} ->
          {:error, trigger_error(name, reason)}
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp set_paused(args, ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, paused} <- Args.required_boolean(args, "paused"),
         {:ok, cause} <- Args.optional(args, "cause"),
         :ok <- Auth.require_pipeline_access(ctx.user, pause_action(paused)) do
      result =
        if paused do
          Pipelines.pause_pipeline(name, ctx.user.username, cause || "")
        else
          Pipelines.unpause_pipeline(name)
        end

      case result do
        {:ok, _pipeline} ->
          Events.pipeline_pause_toggled(ctx.user.username, name, paused)

          Tool.ok(
            "#{name} is now #{if paused, do: "paused", else: "running"}." <>
              if(paused, do: " Cause: #{cause || "none given"}.", else: ""),
            %{"name" => name, "paused" => paused}
          )

        {:error, :pipeline_not_found} ->
          not_found(name)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp unlock(args, ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, confirm} <- Args.boolean(args, "confirm"),
         :ok <- Auth.require_pipeline_access(ctx.user, "release a pipeline's lock") do
      case Pipelines.get_pipeline_by_name(name) do
        nil ->
          not_found(name)

        pipeline ->
          unlock_locked(name, Pipelines.pipeline_locked?(pipeline), confirm, ctx)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp unlock_locked(name, false, _confirm, _ctx) do
    Tool.ok("#{name} is not locked; nothing to release.", %{"name" => name, "changed" => false})
  end

  defp unlock_locked(name, true, false, _ctx) do
    {:error,
     "#{name} is locked, and releasing the lock lets a new run start while the previous " <>
       "one's failure is still there. Call again with `confirm: true` to release it."}
  end

  defp unlock_locked(name, true, true, ctx) do
    case Pipelines.unlock_pipeline(name) do
      {:ok, _pipeline} ->
        Events.pipeline_unlocked(ctx.user.username, name)

        Tool.ok("#{name} is unlocked; it can be triggered again.", %{
          "name" => name,
          "changed" => true
        })

      {:error, :pipeline_not_found} ->
        not_found(name)

      {:error, reason} ->
        {:error, "Could not release the lock of '#{name}': #{inspect(reason)}"}
    end
  end

  defp comment(args, ctx) do
    with {:ok, name} <- Args.required(args, "name"),
         {:ok, counter} <- Args.required_integer(args, "counter"),
         {:ok, comment} <- Args.required(args, "comment"),
         :ok <- Auth.require_pipeline_access(ctx.user, "comment on a pipeline") do
      case Pipelines.add_comment(name, counter, comment) do
        {:ok, _instance} ->
          Events.pipeline_commented(ctx.user.username, name, counter, comment)

          Tool.ok("Comment added to #{name} ##{counter}.", %{"name" => name, "counter" => counter})

        {:error, :instance_not_found} ->
          {:error, "Run ##{counter} of '#{name}' not found."}

        {:error, :pipeline_not_found} ->
          not_found(name)

        {:error, reason} ->
          {:error, "Could not comment on '#{name}': #{inspect(reason)}"}
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  # A fingerprint nobody knows is a typo, and the trigger path ignores it
  # silently — the run would go out on the latest revision instead of the one
  # that was asked for. Naming the ones that do exist is cheaper to fix.
  defp known_materials(name, []) do
    if Pipelines.get_pipeline_by_name(name) do
      {:ok, []}
    else
      not_found(name)
    end
  end

  defp known_materials(name, overrides) do
    case Pipelines.get_pipeline_by_name(name) do
      nil ->
        not_found(name)

      pipeline ->
        materials = pipeline.materials || []
        known = MapSet.new(materials, &Pipelines.material_fingerprint/1)
        unknown = Enum.reject(overrides, &MapSet.member?(known, &1["fingerprint"]))

        if unknown == [] do
          {:ok, overrides}
        else
          {:error,
           "These fingerprints are not materials of '#{name}': " <>
             Enum.map_join(unknown, ", ", &"`#{&1["fingerprint"]}`") <>
             ". Known: " <>
             Enum.map_join(materials, ", ", fn material ->
               "#{material.type} #{material.url} (`#{Pipelines.material_fingerprint(material)}`)"
             end)}
        end
    end
  end

  # The reasons that read the same whatever the pipeline is called.
  @nameless_reasons %{
    :maintenance_mode => "The server is in maintenance mode: no pipeline can be triggered.",
    :disk_space_critical => "The server's disk is critically low, so scheduling is stopped."
  }

  @named_reasons %{
    :pipeline_not_found => "Pipeline '%{name}' not found.",
    :pipeline_paused => "'%{name}' is paused — unpause it with `gocd_set_pipeline_paused` first.",
    :pipeline_locked =>
      "'%{name}' is locked by a failed run — `gocd_unlock_pipeline` releases it.",
    :already_triggered =>
      "'%{name}' was triggered moments ago; this is the trigger debounce, not a failure."
  }

  defp trigger_error(name, {:unconfigured_variable, variable}) do
    "'#{name}' does not declare a variable named `#{variable}`; trigger-time values may " <>
      "only set variables the pipeline defines."
  end

  defp trigger_error(name, reason) do
    reason
    |> error_template()
    |> String.replace("%{name}", name)
  end

  defp error_template(reason) when is_map_key(@nameless_reasons, reason),
    do: Map.fetch!(@nameless_reasons, reason)

  defp error_template(reason) when is_map_key(@named_reasons, reason),
    do: Map.fetch!(@named_reasons, reason)

  defp error_template(reason), do: "Could not trigger '%{name}': #{inspect(reason)}"

  defp pause_action(true), do: "pause a pipeline"
  defp pause_action(false), do: "unpause a pipeline"

  defp not_found(name), do: {:error, "Pipeline '#{name}' not found."}
end
