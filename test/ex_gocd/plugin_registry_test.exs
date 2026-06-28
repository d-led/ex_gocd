defmodule ExGoCD.Plugin.RegistryTest do
  use ExUnit.Case, async: false

  # Test plugin that implements AgentSelector — rejects GPU jobs for elastic agents
  defmodule TestCorpPolicy do
    @behaviour ExGoCD.Plugin.AgentSelector

    @impl true
    def select_candidates(agents, job_spec, _opts) do
      needs_gpu? = "gpu" in (job_spec[:resources] || [])
      elastic_ids = MapSet.new(agents, & &1.elastic_agent_id)

      if needs_gpu? and MapSet.size(elastic_ids) > 0 do
        filtered = Enum.reject(agents, &(&1.elastic_agent_id != nil))
        if filtered == [], do: {:reject, "No non-spot GPU agents"}, else: {:ok, filtered}
      else
        {:ok, agents}
      end
    end
  end

  describe "get/1 with no plugins configured" do
    test "returns nil for all slots" do
      # PluginRegistry is started by the application, no plugins configured in test
      assert ExGoCD.Plugin.Registry.get(:agent_selector) == nil
      assert ExGoCD.Plugin.Registry.get(:auth_provider) == nil
      assert ExGoCD.Plugin.Registry.get(:pipeline_grouper) == nil
      assert ExGoCD.Plugin.Registry.get(:org_hierarchy) == nil
      assert ExGoCD.Plugin.Registry.get(:notification_sink) == nil
    end
  end

  describe "list/0" do
    test "returns all slots with their values" do
      list = ExGoCD.Plugin.Registry.list()
      assert Keyword.has_key?(list, :agent_selector)
      assert Keyword.has_key?(list, :auth_provider)
      assert Keyword.has_key?(list, :pipeline_grouper)
      assert Keyword.has_key?(list, :org_hierarchy)
      assert Keyword.has_key?(list, :notification_sink)
    end

    test "all slots are nil by default" do
      for {_slot, mod} <- ExGoCD.Plugin.Registry.list() do
        assert mod == nil
      end
    end
  end

  describe "AgentSelector behaviour" do
    test "TestCorpPolicy allows non-GPU jobs" do
      agent = %{uuid: "a1", elastic_agent_id: "ea1"}
      assert {:ok, [^agent]} = TestCorpPolicy.select_candidates([agent], %{resources: ["linux"]}, [])
    end

    test "TestCorpPolicy rejects GPU jobs for elastic agents" do
      agent = %{uuid: "a1", elastic_agent_id: "ea1"}
      assert {:reject, _} = TestCorpPolicy.select_candidates([agent], %{resources: ["gpu"]}, [])
    end

    test "TestCorpPolicy allows GPU jobs for non-elastic agents" do
      agent = %{uuid: "a1", elastic_agent_id: nil}
      assert {:ok, [^agent]} = TestCorpPolicy.select_candidates([agent], %{resources: ["gpu"]}, [])
    end
  end
end
