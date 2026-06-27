defmodule ExGoCD.ArtifactStoresTest do
  use ExGoCD.DataCase
  alias ExGoCD.ArtifactStores

  @valid %{plugin_id: "s3", properties: %{"bucket" => "artifacts"}}

  test "CRUD for artifact stores" do
    assert [] = ArtifactStores.list_stores()
    {:ok, store} = ArtifactStores.create_store(@valid)
    assert store.plugin_id == "s3"

    assert [%{}] = ArtifactStores.list_stores()
    {:ok, updated} = ArtifactStores.update_store(store, %{plugin_id: "gcs"})
    assert updated.plugin_id == "gcs"

    {:ok, _} = ArtifactStores.delete_store(store)
    assert [] = ArtifactStores.list_stores()
  end

  test "validation requires plugin_id" do
    {:error, cs} = ArtifactStores.create_store(%{})
    assert "can't be blank" in errors_on(cs).plugin_id
  end
end
