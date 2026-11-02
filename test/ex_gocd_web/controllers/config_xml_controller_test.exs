defmodule ExGoCDWeb.ConfigXmlControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.ConfigSnapshot
  alias ExGoCD.ConfigVersion
  alias ExGoCD.Repo
  alias ExGoCD.SecretConfigs.SecretConfig

  test "the admin page renders", %{conn: conn} do
    body = conn |> get(~p"/admin/config_xml") |> html_response(200)

    assert body =~ "Config XML"
  end

  describe "reverting to a version" do
    test "restores what the XML cannot carry, from the same version's JSON", %{conn: conn} do
      {:ok, _secret} = create_secret_config("vault-terraform")
      {:ok, version} = ConfigSnapshot.snapshot("test", "with a secret config")

      # The secret config is not in the XML, so the JSON restore is the only way
      # it comes back.
      Repo.delete_all(SecretConfig)
      assert Repo.all(SecretConfig) == []

      conn = post(conn, ~p"/admin/config_xml/revert/#{version.id}")

      assert redirected_to(conn) == "/admin/config_xml"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Imported"

      assert %SecretConfig{configuration: %{"address" => "https://vault.test"}} =
               Repo.get_by(SecretConfig, name: "vault-terraform")
    end

    test "a version with no stored XML is refused, and says so", %{conn: conn} do
      version =
        Repo.insert!(%ConfigVersion{
          config_hash: "no-xml-#{System.unique_integer([:positive])}",
          config_json: %{"secret_configs" => []},
          config_xml: nil,
          changed_by: "test",
          change_reason: "never written"
        })

      conn = post(conn, ~p"/admin/config_xml/revert/#{version.id}")

      assert redirected_to(conn) == "/admin/config_xml"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no stored XML"
    end
  end

  defp create_secret_config(name) do
    ExGoCD.SecretConfigs.create_config(%{
      name: name,
      plugin_id: "cd.go.secrets.vault",
      configuration: %{"address" => "https://vault.test"}
    })
  end
end
