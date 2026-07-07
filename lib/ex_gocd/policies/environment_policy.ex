defmodule ExGoCD.Policies.EnvironmentPolicy do
  @moduledoc """
  Authorization policy for environment management — GoCD parity.

  Evaluates role-based policies (GoCD-style RBAC):
    - Admin users can always manage/view all environments
    - Non-admin users: role policies checked for per-environment access
    - Policy format: %{"allow" => [%{"action" => "view", "type" => "environment", "resource" => "UAT"}]}

  Uses Bodyguard for clean policy evaluation.
  """
  use Bodyguard.Policy

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  # ── Actions ──────────────────────────────────────────────────────────────

  # Backward-compatible global actions (used by controllers)
  def authorize(:view_environments, %User{} = user, _params) do
    # In GoCD: any authenticated user can view environments
    if Accounts.admin_configured?() do
      # Any user with a non-guest role can view environments
      if user.username != "guest" and user.roles != [], do: :ok, else: {:error, :forbidden}
    else
      :ok
    end
  end

  # Per-environment actions (for Bodyguard usage in LiveViews)
  def authorize(:view_environment, %User{} = user, %{environment: env_name}) do
    has_permission?(user, "view", "environment", env_name)
  end

  def authorize(:administer_environment, %User{} = user, %{environment: env_name}) do
    has_permission?(user, "administer", "environment", env_name)
  end

  def authorize(:manage_environments, %User{} = user, _params) do
    if not Accounts.admin_configured?() or User.has_role?(user, :admin),
      do: :ok,
      else: {:error, :forbidden}
  end

  def authorize(:trigger_pipeline, %User{} = user, _params) do
    if User.has_role?(user, :admin) or User.has_role?(user, :developer),
      do: :ok,
      else: {:error, :forbidden}
  end

  def authorize(_action, _user, _params), do: false

  # ── Permission evaluation ───────────────────────────────────────────────

  # Global check: any role policy matches (wildcard resource counts)
  def has_permission_global?(%User{} = user, action, type) do
    cond do
      not Accounts.admin_configured?() ->
        true

      User.has_role?(user, :admin) ->
        true

      true ->
        (user.roles || [])
        |> Enum.map(&Accounts.get_role_by_name/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.any?(fn role -> role_allows?(role, action, type, "*") end)
    end
  end

  def has_permission_global?(_user, _action, _type), do: false

  def has_permission?(%User{} = user, action, type, resource) do
    cond do
      # Open mode: no admin configured → everyone has full access
      not Accounts.admin_configured?() ->
        true

      # Admin users always have full access
      User.has_role?(user, :admin) ->
        true

      # Check role policies for per-environment access
      true ->
        (user.roles || [])
        |> Enum.map(&Accounts.get_role_by_name/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.any?(fn role -> role_allows?(role, action, type, resource) end)
    end
  end

  def has_permission?(_user, _action, _type, _resource), do: false

  defp role_allows?(role, action, type, resource) do
    policy = role.policy || %{}
    allows = Map.get(policy, "allow", []) || []

    Enum.any?(allows, fn rule ->
      rule_action = rule["action"] || rule[:action]
      rule_type = rule["type"] || rule[:type]
      rule_resource = rule["resource"] || rule[:resource] || "*"

      rule_action == action and
        rule_type == type and
        (rule_resource == "*" or rule_resource == resource)
    end)
  end
end
