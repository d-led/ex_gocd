defmodule ExGoCDWeb.AdminOtelLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias ExGoCD.Accounts

  setup do
    {:ok, _} =
      Accounts.create_user(%{
        username: "admin",
        display_name: "System Administrator",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, _} =
      Accounts.create_user(%{
        username: "viewer",
        display_name: "Guest",
        roles: [],
        status: "Active"
      })

    :ok
  end

  describe "AdminOtelLive page" do
    setup %{conn: conn} do
      {:ok, conn: log_in_as(conn, "admin")}
    end

    test "renders observability page with SDK status", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Observability"
      assert page_title(view) =~ "Observability"

      # SDK is disabled in test (config/test.exs sets sdk_disabled: true)
      assert html =~ "Disabled"
    end

    test "shows exporter configuration section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Exporter"
      assert html =~ "None (disabled)"
      assert html =~ "ex_gocd_test"
    end

    test "shows instrumentation handler status", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Phoenix"
      assert html =~ "Ecto"
      assert html =~ "Process"
    end

    test "shows environment variables section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Environment Variables"
      assert html =~ "EX_GOCD_NO_OTEL"
      assert html =~ "OTEL_TRACES_EXPORTER"
      assert html =~ "OTEL_SERVICE_NAME"
    end

    test "shows setup guide with docker compose instructions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Setup Guide"
      assert html =~ "jaeger otel-collector"
      assert html =~ "EX_GOCD_NO_OTEL=1"
      assert html =~ "OTEL_TRACES_EXPORTER=otlp"
    end

    test "has refresh button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Refresh Now"
    end

    test "collector status shows N/A when disabled", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/observability")

      assert html =~ "Collector"
      # In test, exporter is :none, so collector should show N/A
      assert html =~ "N/A"
    end
  end

  describe "AdminOtelLive access control" do
    test "redirects non-admin users away from observability page", %{conn: conn} do
      conn = log_in_as(conn, "viewer")
      {:error, {:redirect, _}} = live(conn, ~p"/admin/observability")
    end
  end

  describe "ExGoCD.Otel.Admin status" do
    test "reports SDK as disabled in test environment" do
      status = ExGoCD.Otel.Admin.status()

      assert status.sdk_enabled == false
      assert status.sdk_disabled == true
      assert status.no_otel_env == false
    end

    test "reports exporter as :none in test environment" do
      status = ExGoCD.Otel.Admin.status()

      assert status.exporter == :none
      assert status.collector_reachable == :disabled
    end

    test "reports service name from config" do
      status = ExGoCD.Otel.Admin.status()

      assert status.service_name == "ex_gocd_test"
    end

    test "reports environment variables" do
      status = ExGoCD.Otel.Admin.status()

      assert is_map(status.env_vars)
      assert Map.has_key?(status.env_vars, "EX_GOCD_NO_OTEL")
      assert Map.has_key?(status.env_vars, "OTEL_TRACES_EXPORTER")
      assert Map.has_key?(status.env_vars, "OTEL_EXPORTER_OTLP_ENDPOINT")
      assert Map.has_key?(status.env_vars, "OTEL_SERVICE_NAME")
    end

    test "reports instrumentation status map" do
      status = ExGoCD.Otel.Admin.status()

      assert is_map(status.instrumentation)
      assert Map.has_key?(status.instrumentation, :phoenix)
      assert Map.has_key?(status.instrumentation, :ecto)
      assert Map.has_key?(status.instrumentation, :process_propagator)
    end

    test "status map has all expected keys" do
      status = ExGoCD.Otel.Admin.status()

      expected_keys = [
        :sdk_enabled,
        :sdk_disabled,
        :exporter,
        :otlp_endpoint,
        :service_name,
        :env_vars,
        :instrumentation,
        :collector_reachable,
        :no_otel_env
      ]

      for key <- expected_keys do
        assert Map.has_key?(status, key), "status missing key: #{key}"
      end
    end
  end
end
