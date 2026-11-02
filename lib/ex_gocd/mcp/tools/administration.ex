defmodule ExGoCD.Mcp.Tools.Administration do
  @moduledoc """
  The operational acts: stopping and resuming scheduling, taking a backup,
  refreshing a config repository, and looking at the people who can do any of
  this.

  These are an administrator's tools, and they say so: each one asks for the
  administrator check `ExGoCD.Accounts.admin?/1` makes — which is GoCD's own
  rule, open mode included — and the ones that change the server are recorded in
  the audit log under the caller's name.

  Enabling maintenance mode asks for `confirm` because it stops every pipeline
  from being triggered; a caller that meant to read the flag should not be able
  to stop a server by mistyping a name.
  """

  alias ExGoCD.{Accounts, Backup, ConfigRepos, MaintenanceMode}
  alias ExGoCD.AuditLog.Events
  alias ExGoCD.Mcp.{Args, Auth, Render, Tool}

  @names ~w(gocd_set_maintenance_mode gocd_create_backup gocd_backup_status gocd_config_repos
            gocd_refresh_config_repo gocd_list_users)

  @tools [
    %{
      "name" => "gocd_set_maintenance_mode",
      "title" => "Stop or resume scheduling",
      "description" =>
        "Turns maintenance mode on or off. On, pipelines in progress continue and agents " <>
          "finish their jobs, but nothing new is triggered or scheduled — the switch for " <>
          "taking a server out of service. Answers without changing anything unless " <>
          "`confirm` is true, and is an administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "enabled" => %{
            "type" => "boolean",
            "description" => "`true` stops scheduling, `false` resumes it."
          },
          "confirm" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "True changes it; false only reports what would change."
          }
        },
        "required" => ["enabled"]
      },
      "annotations" => Tool.destructive()
    },
    %{
      "name" => "gocd_create_backup",
      "title" => "Take a database backup",
      "description" =>
        "Starts a backup of this server's database, as the admin page's backup button does. " <>
          "It runs in the background; `gocd_backup_status` says how it is going. An " <>
          "administrator's act.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_backup_status",
      "title" => "How the last backup went",
      "description" =>
        "Whether a backup is idle, running, or finished, and the message it left — the " <>
          "answer to \"did the backup work\".",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_config_repos",
      "title" => "The config repositories",
      "description" =>
        "Each config repository this server reads pipelines from: its url, branch, source " <>
          "type, when it was last parsed, and the error it last reported. Plugin " <>
          "configuration is named, never shown — it can carry credentials. A pipeline with " <>
          "a `config_repo_id` is defined in one of these and is not edited here.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_refresh_config_repo",
      "title" => "Re-read a config repository",
      "description" =>
        "Asks the poller to re-read one config repository now instead of at its next " <>
          "interval — how a pipeline definition added upstream appears here. Answers with " <>
          "the repository as it was; the parse happens in the poller. An administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer", "minimum" => 1, "description" => "The repository's id."}
        },
        "required" => ["id"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_list_users",
      "title" => "The people who can use this server",
      "description" =>
        "Every account, its display name, its roles and whether it is active. Filter by " <>
          "words in the username or display name. An administrator's act, as on the users " <>
          "API — whoever may read this list can ask who to disable.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Words the username or display name must contain."
          },
          "role" => %{
            "type" => "string",
            "description" => "Only users holding this role, e.g. `admin`."
          }
        }
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
  def call("gocd_set_maintenance_mode", args, ctx), do: set_maintenance_mode(args, ctx)
  def call("gocd_create_backup", args, ctx), do: create_backup(args, ctx)
  def call("gocd_backup_status", args, ctx), do: backup_status(args, ctx)
  def call("gocd_config_repos", args, ctx), do: config_repos(args, ctx)
  def call("gocd_refresh_config_repo", args, ctx), do: refresh_config_repo(args, ctx)
  def call("gocd_list_users", args, ctx), do: list_users(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp set_maintenance_mode(args, ctx) do
    with {:ok, enabled} <- Args.required_boolean(args, "enabled"),
         {:ok, confirm} <- Args.boolean(args, "confirm"),
         :ok <- Auth.require_admin(ctx.user, "change maintenance mode"),
         :ok <- confirm_if_enabling(enabled, confirm) do
      case change_maintenance(enabled) do
        {:ok, state} ->
          Events.maintenance_mode_toggled(ctx.user.username, enabled)

          Tool.ok(
            "Maintenance mode is #{state}. " <>
              if(enabled,
                do: "Nothing new will be triggered or scheduled until it is turned off.",
                else: "Pipelines can be triggered and scheduled again."
              ),
            %{"maintenance_mode" => enabled}
          )

        {:error, :already_enabled} ->
          Tool.ok("Maintenance mode was already on.", %{"maintenance_mode" => true})

        {:error, :already_disabled} ->
          Tool.ok("Maintenance mode was already off.", %{"maintenance_mode" => false})
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp confirm_if_enabling(false, _confirm), do: :ok

  defp confirm_if_enabling(true, false) do
    {:error,
     "Turning maintenance mode on stops every pipeline from being triggered or scheduled; " <>
       "runs in progress continue. Call again with `confirm: true` to turn it on."}
  end

  defp confirm_if_enabling(true, true), do: :ok

  defp change_maintenance(true) do
    case MaintenanceMode.enable() do
      {:ok, :enabled} -> {:ok, "on"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp change_maintenance(false) do
    case MaintenanceMode.disable() do
      {:ok, :disabled} -> {:ok, "off"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_backup(_args, ctx) do
    case Auth.require_admin(ctx.user, "take a backup") do
      :ok -> start_backup(ctx)
      {:error, message} -> {:error, message}
    end
  end

  defp start_backup(ctx) do
    case Backup.create() do
      :ok ->
        Events.backup_requested(ctx.user.username)

        Tool.ok(
          "A backup has started; it runs in the background. `gocd_backup_status` says how it went.",
          %{"started" => true}
        )

      {:error, :already_running} ->
        Tool.ok("A backup is already running.", %{"started" => false, "running" => true})
    end
  end

  defp backup_status(_args, _ctx) do
    status = Backup.status()

    Tool.ok("Backup: #{status.status}#{message_suffix(status.message)}", %{
      "status" => status.status,
      "message" => status.message
    })
  end

  defp message_suffix(message) when message in [nil, ""], do: ""
  defp message_suffix(message), do: " — #{message}"

  defp config_repos(_args, _ctx) do
    repositories = ConfigRepos.list_config_repos()

    text =
      if repositories == [] do
        "No config repositories are configured: every pipeline here is edited on this server."
      else
        "#{length(repositories)} config repositor(y/ies)\n\n" <>
          Render.table(
            ["ID", "URL", "BRANCH", "SOURCE", "LAST PARSED", "ERROR"],
            Enum.map(repositories, fn repository ->
              [
                repository.id,
                repository.url,
                repository.branch,
                repository.source_type,
                Render.timestamp(repository.last_parsed_at),
                repository.error_message
              ]
            end)
          )
      end

    Tool.ok(text, %{"config_repos" => Enum.map(repositories, &repository_map/1)})
  end

  defp refresh_config_repo(args, ctx) do
    with {:ok, request} <- Args.all(args, id: :integer),
         :ok <- Auth.require_admin(ctx.user, "refresh a config repository") do
      refresh_repository(request.id)
    else
      {:error, message} -> {:error, message}
    end
  end

  defp refresh_repository(id) do
    case ConfigRepos.get_config_repo(id) do
      nil -> {:error, "Config repository #{id} not found."}
      repository -> request_refresh(id, repository)
    end
  end

  defp request_refresh(id, repository) do
    case ConfigRepos.refresh_config_repo(repository) do
      {:ok, _repository} ->
        Tool.ok(
          "Config repository #{id} (#{repository.url}) will be re-read by the poller. " <>
            "`gocd_config_repos` shows when it last parsed, and any error it reports.",
          %{"id" => id, "refresh_requested" => true}
        )

      {:error, reason} ->
        {:error, "Could not refresh config repository #{id}: #{reason}"}
    end
  end

  defp list_users(args, ctx) do
    with {:ok, query} <- Args.optional(args, "query"),
         {:ok, role} <- Args.optional(args, "role"),
         :ok <- Auth.require_admin(ctx.user, "list the users of this server") do
      users =
        Accounts.list_users()
        |> Enum.filter(&matches?(&1, query, role))

      text =
        if users == [] do
          "No users match."
        else
          "#{length(users)} user(s)\n\n" <>
            Render.table(
              ["USERNAME", "DISPLAY NAME", "STATUS", "ROLES"],
              Enum.map(users, fn user ->
                [user.username, user.display_name, user.status, user.roles]
              end)
            )
        end

      Tool.ok(text, %{
        "users" =>
          Enum.map(users, fn user ->
            %{
              "username" => user.username,
              "display_name" => user.display_name,
              "status" => user.status,
              "roles" => user.roles || []
            }
          end)
      })
    else
      {:error, message} -> {:error, message}
    end
  end

  # `configuration` is where a plugin keeps its settings, and a git credential can
  # be one of them: the keys are the answer, the values are not ours to repeat.
  defp repository_map(repository) do
    %{
      "id" => repository.id,
      "url" => repository.url,
      "branch" => repository.branch,
      "material_type" => repository.material_type,
      "source_type" => repository.source_type,
      "plugin_id" => repository.plugin_id,
      "configuration_keys" => repository.configuration |> Map.keys() |> Enum.sort(),
      "last_parsed_at" => Render.timestamp(repository.last_parsed_at),
      "error_message" => repository.error_message
    }
  end

  defp matches?(user, query, role) do
    text_matches?(user, query) and role_matches?(user, role)
  end

  defp text_matches?(_user, nil), do: true

  defp text_matches?(user, query) do
    haystack = String.downcase("#{user.username} #{user.display_name}")
    String.contains?(haystack, String.downcase(query))
  end

  defp role_matches?(_user, nil), do: true
  defp role_matches?(user, role), do: role in (user.roles || [])
end
