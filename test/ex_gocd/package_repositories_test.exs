defmodule ExGoCD.PackageRepositoriesTest do
  use ExGoCD.DataCase
  alias ExGoCD.PackageRepositories

  @valid %{name: "docker-hub", plugin_id: "docker-registry", configuration: %{"registry_url" => "https://index.docker.io"}}

  test "CRUD for package repositories" do
    assert [] = PackageRepositories.list_repos()

    {:ok, repo} = PackageRepositories.create_repo(@valid)
    assert repo.name == "docker-hub"

    assert [%{}] = PackageRepositories.list_repos()
    assert %{} = PackageRepositories.get_repo!(repo.id)

    {:ok, updated} = PackageRepositories.update_repo(repo, %{name: "docker-hub-v2"})
    assert updated.name == "docker-hub-v2"

    {:ok, _} = PackageRepositories.delete_repo(repo)
    assert [] = PackageRepositories.list_repos()
  end

  test "validation requires name and plugin_id" do
    {:error, cs} = PackageRepositories.create_repo(%{})
    assert "can't be blank" in errors_on(cs).name
    assert "can't be blank" in errors_on(cs).plugin_id
  end

  test "list_by_plugin filters" do
    PackageRepositories.create_repo(%{name: "a", plugin_id: "docker", configuration: %{}})
    PackageRepositories.create_repo(%{name: "b", plugin_id: "maven", configuration: %{}})
    assert length(PackageRepositories.list_by_plugin("docker")) == 1
  end
end
