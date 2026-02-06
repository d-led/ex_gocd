defmodule ExGoCD.Agents.Agent do
  @moduledoc """
  Agent configuration schema representing a GoCD agent.

  This represents the PERSISTENT configuration of an agent, not its runtime state.
  Runtime information (build status, disk space, etc.) is tracked in memory via AgentInstance.

  Based on GoCD source: config/config-api/.../Agent.java
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          uuid: String.t(),
          hostname: String.t(),
          ipaddress: String.t(),
          elastic_agent_id: String.t() | nil,
          elastic_plugin_id: String.t() | nil,
          disabled: boolean(),
          deleted: boolean(),
          environments: [String.t()],
          resources: [String.t()],
          cookie: String.t() | nil,
          working_dir: String.t() | nil,
          operating_system: String.t() | nil,
          free_space: integer() | nil,
          state: String.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "agents" do
    field :uuid, :string
    field :hostname, :string
    # Note: GoCD uses "ipaddress" not "ip_address"
    field :ipaddress, :string
    field :elastic_agent_id, :string
    field :elastic_plugin_id, :string
    field :disabled, :boolean, default: false
    field :deleted, :boolean, default: false
    field :environments, {:array, :string}, default: []
    field :resources, {:array, :string}, default: []
    field :cookie, :string
    # Runtime fields
    field :working_dir, :string
    field :operating_system, :string
    field :free_space, :integer
    field :state, :string, default: "Idle"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating an agent.

  Validates according to GoCD's Agent.validate() method.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :uuid,
      :hostname,
      :ipaddress,
      :elastic_agent_id,
      :elastic_plugin_id,
      :disabled,
      :deleted,
      :environments,
      :resources,
      :cookie,
      :working_dir,
      :operating_system,
      :free_space,
      :state
    ])
    |> validate_required([:uuid, :hostname, :ipaddress])
    |> validate_format(:uuid, ~r/^[a-f0-9-]{36}$/i, message: "must be a valid UUID")
    |> validate_ip_address()
    |> validate_resources()
    |> unique_constraint(:uuid)
  end

  @doc """
  Changeset for agent registration (initial creation).
  """
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :uuid,
      :hostname,
      :ipaddress,
      :elastic_agent_id,
      :elastic_plugin_id,
      :environments,
      :resources,
      :cookie,
      :working_dir,
      :operating_system,
      :free_space,
      :state
    ])
    |> validate_required([:uuid, :hostname, :ipaddress])
    |> validate_format(:uuid, ~r/^[a-f0-9-]{36}$/i, message: "must be a valid UUID")
    |> validate_ip_address()
    |> validate_resources()
    |> put_change(:disabled, false)
    |> put_change(:deleted, false)
    |> put_change(:state, "Idle")
    |> unique_constraint(:uuid)
  end

  defp validate_ip_address(changeset) do
    validate_change(changeset, :ipaddress, fn :ipaddress, ip ->
      case ip do
        "" ->
          [ipaddress: "cannot be empty if present"]

        ip when is_binary(ip) ->
          # Basic IP validation (IPv4 or IPv6)
          case :inet.parse_address(String.to_charlist(ip)) do
            {:ok, _} -> []
            {:error, _} -> [ipaddress: "is not a valid IP address"]
          end

        _ ->
          [ipaddress: "must be a string"]
      end
    end)
  end

  defp validate_resources(changeset) do
    resources = get_field(changeset, :resources) || []
    elastic_agent_id = get_field(changeset, :elastic_agent_id)
    elastic_plugin_id = get_field(changeset, :elastic_plugin_id)

    # Elastic agents cannot have resources (per Agent.validateResources())
    if is_elastic?(elastic_agent_id, elastic_plugin_id) and length(resources) > 0 do
      add_error(changeset, :resources, "Elastic agents cannot have resources")
    else
      changeset
    end
  end

  defp is_elastic?(elastic_agent_id, elastic_plugin_id) do
    not is_nil(elastic_agent_id) and elastic_agent_id != "" and
      not is_nil(elastic_plugin_id) and elastic_plugin_id != ""
  end

  @doc """
  Checks if agent is an elastic agent.
  """
  @spec elastic?(t()) :: boolean()
  def elastic?(%__MODULE__{} = agent) do
    is_elastic?(agent.elastic_agent_id, agent.elastic_plugin_id)
  end

  @doc """
  Checks if agent is enabled.
  """
  @spec enabled?(t()) :: boolean()
  def enabled?(%__MODULE__{disabled: disabled}), do: not disabled

  @doc """
  Checks if agent has all required resources.
  """
  @spec has_all_resources?(t(), [String.t()]) :: boolean()
  def has_all_resources?(%__MODULE__{resources: agent_resources}, required_resources) do
    agent_resources_lower = Enum.map(agent_resources, &String.downcase/1) |> MapSet.new()
    required_resources_lower = Enum.map(required_resources, &String.downcase/1) |> MapSet.new()

    MapSet.subset?(required_resources_lower, agent_resources_lower)
  end

  @doc """
  Checks if agent belongs to any of the given environments.
  """
  @spec in_environment?(t(), String.t()) :: boolean()
  def in_environment?(%__MODULE__{environments: envs}, environment) do
    environment in envs
  end
end
