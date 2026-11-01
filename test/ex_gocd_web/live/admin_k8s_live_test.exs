defmodule ExGoCDWeb.AdminK8sLiveTest do
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ElasticAgentProfiles

  describe "the elastic agents page" do
    test "lists the cluster profiles it holds", %{conn: conn} do
      {:ok, _profile} = create_cluster_profile("team-cluster")

      {:ok, _view, html} = live(conn, ~p"/admin/elastic_agents")

      assert html =~ "team-cluster"
      assert html =~ "ex_gocd.elasticagent.kubernetes"
    end

    test "says a cluster profile cannot be saved without a name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/elastic_agents")
      profiles_before = length(ClusterProfiles.list_profiles())

      view |> element("button", "+ Add Cluster") |> render_click()

      html =
        view
        |> form("form[phx-submit='save_cluster']",
          cluster: %{name: "", server_url: "https://k8s.invalid:6443"}
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert length(ClusterProfiles.list_profiles()) == profiles_before
    end

    test "a saved cluster profile appears in the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/elastic_agents")

      view |> element("button", "+ Add Cluster") |> render_click()

      html =
        view
        |> form("form[phx-submit='save_cluster']",
          cluster: %{
            name: "saved-cluster",
            server_url: "https://k8s.invalid:6443",
            namespace: "ci"
          }
        )
        |> render_submit()

      assert html =~ "Cluster profile saved."
      assert html =~ "saved-cluster"
      assert html =~ "https://k8s.invalid:6443"

      assert stored_cluster_profile("saved-cluster").properties["namespace"] == "ci"
    end

    test "a deleted cluster profile leaves the list", %{conn: conn} do
      {:ok, profile} = create_cluster_profile("goes-away")

      {:ok, view, html} = live(conn, ~p"/admin/elastic_agents")
      assert html =~ "goes-away"

      view
      |> element("button[phx-click='delete_cluster'][phx-value-id='#{profile.id}']")
      |> render_click()

      refute render(view) =~ "goes-away"
      assert ClusterProfiles.get_profile(profile.id) == nil
    end

    test "an agent profile is saved against the cluster it names", %{conn: conn} do
      {:ok, cluster} = create_cluster_profile("agent-cluster")

      {:ok, view, _html} = live(conn, ~p"/admin/elastic_agents")

      view |> element("button", "+ Add Agent Profile") |> render_click()

      html =
        view
        |> form("form[phx-submit='save_agent']",
          agent: %{
            name: "docker-agents",
            cluster_profile_id: cluster.id,
            image: "gocd/gocd-agent-docker-24.5.0",
            min_memory: "1Gi",
            max_memory: "3Gi"
          }
        )
        |> render_submit()

      assert html =~ "Elastic agent profile saved."
      assert html =~ "docker-agents"

      stored = stored_agent_profile("docker-agents")
      assert stored.cluster_profile_id == cluster.id
      assert stored.properties["MaxMemory"] == "3Gi"
    end
  end

  defp create_cluster_profile(name) do
    ClusterProfiles.create_profile(%{
      name: name,
      plugin_id: "ex_gocd.elasticagent.kubernetes",
      properties: %{"kubernetes_cluster_url" => "https://k8s.invalid:6443"}
    })
  end

  defp stored_cluster_profile(name) do
    ClusterProfiles.list_profiles() |> Enum.find(&(&1.name == name))
  end

  defp stored_agent_profile(name) do
    ElasticAgentProfiles.list_profiles() |> Enum.find(&(&1.name == name))
  end
end
