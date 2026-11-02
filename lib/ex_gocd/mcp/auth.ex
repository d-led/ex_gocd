defmodule ExGoCD.Mcp.Auth do
  @moduledoc """
  Who is allowed to do what through the MCP server.

  The rules are the ones the web UI and the JSON API already apply, not new
  ones: a pipeline operation is allowed when
  `ExGoCD.Policies.EnvironmentPolicy` allows `:trigger_pipeline`, and an
  administrative change (an agent's configuration, the config XML) is allowed
  when the caller is an administrator — where "open mode", a server with no
  administrator configured yet, makes every caller one, exactly as
  `ExGoCDWeb.Plugs.AdminApiPlug` does.

  A tool that would fail the check says so in words instead of returning
  forbidden silently: the message is shown to the model that made the call, and
  "you may not do this" is an answer it can act on.
  """

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  @type denial :: {:error, String.t()}

  @doc "Whether these credentials may trigger, approve or cancel a pipeline."
  @spec can_operate_pipelines?(User.t()) :: boolean()
  def can_operate_pipelines?(%User{} = user) do
    ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user)
  end

  @doc "Whether these credentials may change server configuration or agents."
  @spec admin?(User.t()) :: boolean()
  def admin?(%User{} = user), do: Accounts.admin?(user)

  @doc """
  The pipeline-operation check as a tool result.

  `action` names the act in the refusal — "pause a pipeline", "trigger a
  pipeline" — so the caller learns which permission it lacks.
  """
  @spec require_pipeline_access(User.t(), String.t()) :: :ok | denial()
  def require_pipeline_access(user, action) do
    if can_operate_pipelines?(user) do
      :ok
    else
      {:error,
       "Your credentials may not #{action}. In this server that is the " <>
         "`trigger_pipeline` permission; ask an administrator for it."}
    end
  end

  @doc "The administrative check as a tool result."
  @spec require_admin(User.t(), String.t()) :: :ok | denial()
  def require_admin(user, action) do
    if admin?(user) do
      :ok
    else
      {:error,
       "Only an administrator may #{action}. Your credentials are those of " <>
         "`#{user.username}`."}
    end
  end
end
