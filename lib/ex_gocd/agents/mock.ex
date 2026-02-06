defmodule ExGoCD.Agents.Mock do
  @moduledoc """
  Mock agent data for UI development and testing.

  Enable mock mode by setting: USE_MOCK_DATA=true

  This allows UI development without a database connection.
  """

  alias ExGoCD.Agents.Agent

  @doc """
  Returns a list of mock agents with various states for UI testing.
  """
  def list_agents do
    [
      # Idle, enabled agent
      %Agent{
        id: 1,
        uuid: "00000000-0000-0000-0000-000000000001",
        hostname: "build-agent-01.example.com",
        ipaddress: "192.168.1.10",
        elastic_agent_id: nil,
        elastic_plugin_id: nil,
        disabled: false,
        deleted: false,
        environments: ["production", "staging"],
        resources: ["docker", "linux", "chrome"],
        cookie: "mock-cookie-1",
        working_dir: "/var/lib/gocd-agent",
        operating_system: "Linux (Ubuntu 22.04)",
        free_space: 50_000_000_000,
        # 50 GB
        state: "Idle",
        inserted_at: ~U[2026-01-01 10:00:00Z],
        updated_at: ~U[2026-02-06 10:00:00Z]
      },

      # Building agent
      %Agent{
        id: 2,
        uuid: "00000000-0000-0000-0000-000000000002",
        hostname: "build-agent-02.example.com",
        ipaddress: "192.168.1.11",
        elastic_agent_id: nil,
        elastic_plugin_id: nil,
        disabled: false,
        deleted: false,
        environments: ["production"],
        resources: ["docker", "linux", "maven"],
        cookie: "mock-cookie-2",
        working_dir: "/var/lib/gocd-agent",
        operating_system: "Linux (Ubuntu 22.04)",
        free_space: 25_000_000_000,
        # 25 GB
        state: "Building",
        inserted_at: ~U[2026-01-01 10:00:00Z],
        updated_at: ~U[2026-02-06 10:30:00Z]
      },

      # Disabled agent
      %Agent{
        id: 3,
        uuid: "00000000-0000-0000-0000-000000000003",
        hostname: "build-agent-03.example.com",
        ipaddress: "192.168.1.12",
        elastic_agent_id: nil,
        elastic_plugin_id: nil,
        disabled: true,
        deleted: false,
        environments: ["staging"],
        resources: ["docker", "windows"],
        cookie: "mock-cookie-3",
        working_dir: "C:\\gocd-agent",
        operating_system: "Windows Server 2019",
        free_space: 100_000_000_000,
        # 100 GB
        state: "Idle",
        inserted_at: ~U[2026-01-01 10:00:00Z],
        updated_at: ~U[2026-02-05 15:00:00Z]
      },

      # Elastic agent (Kubernetes)
      %Agent{
        id: 4,
        uuid: "00000000-0000-0000-0000-000000000004",
        hostname: "elastic-agent-k8s-abc123",
        ipaddress: "10.244.0.15",
        elastic_agent_id: "k8s-elastic-agent-abc123",
        elastic_plugin_id: "cd.go.contrib.elastic-agent.kubernetes",
        disabled: false,
        deleted: false,
        environments: [],
        resources: ["kubernetes", "docker"],
        cookie: "mock-cookie-4",
        working_dir: "/tmp/gocd-agent",
        operating_system: "Linux (Alpine 3.18)",
        free_space: 10_000_000_000,
        # 10 GB
        state: "Building",
        inserted_at: ~U[2026-02-06 09:00:00Z],
        updated_at: ~U[2026-02-06 10:45:00Z]
      },

      # Lost contact agent
      %Agent{
        id: 5,
        uuid: "00000000-0000-0000-0000-000000000005",
        hostname: "build-agent-offline",
        ipaddress: "192.168.1.13",
        elastic_agent_id: nil,
        elastic_plugin_id: nil,
        disabled: false,
        deleted: false,
        environments: ["development"],
        resources: ["docker", "linux"],
        cookie: "mock-cookie-5",
        working_dir: "/var/lib/gocd-agent",
        operating_system: "Linux (Ubuntu 20.04)",
        free_space: 5_000_000_000,
        # 5 GB
        state: "LostContact",
        inserted_at: ~U[2026-01-15 10:00:00Z],
        updated_at: ~U[2026-02-01 08:00:00Z]
      },

      # Agent with no resources or environments
      %Agent{
        id: 6,
        uuid: "00000000-0000-0000-0000-000000000006",
        hostname: "vanilla-agent",
        ipaddress: "192.168.1.14",
        elastic_agent_id: nil,
        elastic_plugin_id: nil,
        disabled: false,
        deleted: false,
        environments: [],
        resources: [],
        cookie: "mock-cookie-6",
        working_dir: "/home/go/agent",
        operating_system: "macOS 14.0 (Sonoma)",
        free_space: 200_000_000_000,
        # 200 GB
        state: "Idle",
        inserted_at: ~U[2026-02-05 12:00:00Z],
        updated_at: ~U[2026-02-06 09:00:00Z]
      },

      # Agent with low disk space
      %Agent{
        id: 7,
        uuid: "00000000-0000-0000-0000-000000000007",
        hostname: "build-agent-low-space",
        ipaddress: "192.168.1.15",
        elastic_agent_id: nil,
        elastic_plugin_id: nil,
        disabled: false,
        deleted: false,
        environments: ["testing"],
        resources: ["docker", "nodejs"],
        cookie: "mock-cookie-7",
        working_dir: "/var/lib/gocd-agent",
        operating_system: "Linux (Debian 11)",
        free_space: 500_000_000,
        # 500 MB - low!
        state: "Idle",
        inserted_at: ~U[2026-01-20 10:00:00Z],
        updated_at: ~U[2026-02-06 10:50:00Z]
      }
    ]
  end

  @doc """
  Returns a mock agent by UUID.
  """
  def get_agent_by_uuid(uuid) do
    Enum.find(list_agents(), fn agent -> agent.uuid == uuid end)
  end

  @doc """
  Returns mock active agents (not disabled, not deleted).
  """
  def list_active_agents do
    list_agents()
    |> Enum.reject(&(&1.disabled or &1.deleted))
  end

  @doc """
  Mock enable agent.
  """
  def enable_agent(uuid) when is_binary(uuid) do
    case get_agent_by_uuid(uuid) do
      nil -> {:error, :not_found}
      agent -> {:ok, %{agent | disabled: false}}
    end
  end

  @doc """
  Mock disable agent.
  """
  def disable_agent(uuid) when is_binary(uuid) do
    case get_agent_by_uuid(uuid) do
      nil -> {:error, :not_found}
      agent -> {:ok, %{agent | disabled: true}}
    end
  end

  @doc """
  Mock delete agent.
  """
  def delete_agent(uuid) when is_binary(uuid) do
    case get_agent_by_uuid(uuid) do
      nil -> {:error, :not_found}
      _agent -> {:ok, :deleted}
    end
  end

  @doc """
  Mock register agent.
  """
  def register_agent(attrs) do
    agent = %Agent{
      id: :rand.uniform(10000),
      uuid: attrs["uuid"] || Ecto.UUID.generate(),
      hostname: attrs["hostname"] || "mock-agent",
      ipaddress: attrs["ipaddress"] || "127.0.0.1",
      elastic_agent_id: attrs["elastic_agent_id"],
      elastic_plugin_id: attrs["elastic_plugin_id"],
      disabled: false,
      deleted: false,
      environments: attrs["environments"] || [],
      resources: attrs["resources"] || [],
      cookie: attrs["cookie"],
      working_dir: attrs["working_dir"],
      operating_system: attrs["operating_system"],
      free_space: attrs["free_space"],
      state: attrs["state"] || "Idle",
      inserted_at: NaiveDateTime.utc_now(),
      updated_at: NaiveDateTime.utc_now()
    }

    {:ok, agent}
  end
end
