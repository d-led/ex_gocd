defmodule ExGoCDWeb.AdminAgentController do
  @moduledoc """
  Controller for original GoCD agent registration endpoints.

  Implements the legacy `/admin/agent` endpoints for backward compatibility
  with existing GoCD agents.

  Original GoCD endpoints:
  - POST /admin/agent - Form-based agent registration
  - GET /admin/agent/token - Get registration token for agent
  - GET /admin/agent/root_certificate - Answers 404: this server serves no TLS
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Agents
  require Logger

  @doc """
  POST /admin/agent

  Legacy GoCD agent registration endpoint using form data.
  This matches the original GoCD API that agents expect.

  Form params:
    - hostname: Agent hostname (required)
    - uuid: Agent UUID (required)
    - location: Working directory path
    - usablespace: Available disk space
    - operatingSystem: OS information
    - agentAutoRegisterKey: Auto-registration key (optional)
    - agentAutoRegisterResources: Comma-separated resources (optional)
    - agentAutoRegisterEnvironments: Comma-separated environments (optional)
    - agentAutoRegisterHostname: Override hostname (optional)
    - elasticAgentId: Elastic agent ID (optional)
    - elasticPluginId: Elastic plugin ID (optional)
    - token: Registration token (optional)
    - ipAddress: Agent IP address (optional)
  """
  def register(conn, params) do
    Logger.info("Agent registration request: #{inspect(params)}")

    # Auto-enable new agents in dev/demo (default true in dev, or when EX_GOCD_AUTO_ENABLE_AGENTS=true)
    auto_enable =
      System.get_env("EX_GOCD_AUTO_ENABLE_AGENTS") in ["1", "true", "TRUE"] or
        (dev_env?() and System.get_env("EX_GOCD_AUTO_ENABLE_AGENTS") != "0")

    base_attrs = %{
      "uuid" => params["uuid"],
      "hostname" => params["hostname"] || params["agentAutoRegisterHostname"],
      "ipaddress" => params["ipAddress"] || "0.0.0.0",
      "working_dir" => params["location"],
      "free_space" => parse_free_space(params["usablespace"]),
      "operating_system" => params["operatingSystem"],
      "elastic_agent_id" => params["elasticAgentId"],
      "elastic_plugin_id" => params["elasticPluginId"],
      "resources" => parse_comma_separated(params["agentAutoRegisterResources"]),
      "environments" => parse_comma_separated(params["agentAutoRegisterEnvironments"]),
      "cookie" => params["token"],
      "state" => "Idle"
    }

    attrs = if auto_enable, do: Map.put(base_attrs, "disabled", false), else: base_attrs

    # Validate required fields
    unless attrs["uuid"] && attrs["hostname"] do
      Logger.error(
        "Missing required fields: uuid=#{attrs["uuid"]}, hostname=#{attrs["hostname"]}"
      )

      conn
      |> put_status(:bad_request)
      |> json(%{error: "Missing required fields: uuid and hostname"})
    else
      case Agents.register_agent(attrs) do
        {:ok, agent} ->
          Logger.info("Agent registered successfully: #{agent.uuid}")

          # For HTTP (non-TLS), return empty 200 response like original GoCD
          conn
          |> put_status(:ok)
          |> text("")

        {:error, changeset} ->
          Logger.error("Agent registration failed: #{inspect(changeset.errors)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Registration failed", details: translate_errors(changeset)})
      end
    end
  end

  @doc """
  GET /admin/agent/token?uuid=<uuid>

  Returns a registration token for the agent.
  In the simplified implementation, we generate a simple token.
  """
  def token(conn, %{"uuid" => uuid}) do
    Logger.info("Token request for agent: #{uuid}")

    # Demo/dev: shared cookie so phx.server + start-agent and docker-compose always match
    token =
      case System.get_env("EX_GOCD_DEMO_COOKIE") do
        nil ->
          if dev_env?(),
            do: "ex-gocd-demo-cookie",
            else: "agent-token-#{uuid}-#{:os.system_time(:millisecond)}"

        demo ->
          String.trim(demo)
      end

    conn
    |> put_resp_content_type("text/plain")
    |> text(token)
  end

  def token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing uuid parameter"})
  end

  defp dev_env? do
    Application.get_env(:ex_gocd, :env) == :dev
  end

  @doc """
  GET /admin/agent/root_certificate

  This server does not terminate TLS, so it has no CA of its own to hand out:
  the certificate an agent should trust belongs to whatever sits in front of
  the server — oauth2-proxy, a load balancer. Answering 404 says that plainly;
  the certificate-shaped placeholder that used to be served here was worse than
  nothing, because a trusting agent would pin it. The Go agent asks only when
  its server URL is `https` (`agent/internal/registration`).
  """
  def root_certificate(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_resp_content_type("text/plain")
    |> text("This server does not serve TLS; it is expected behind a proxy that does.\n")
  end

  # Helper to parse comma-separated values into array
  defp parse_comma_separated(nil), do: []
  defp parse_comma_separated(""), do: []

  defp parse_comma_separated(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Helper to parse free space value
  defp parse_free_space(nil), do: nil

  defp parse_free_space(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_free_space(num) when is_integer(num), do: num

  # Helper to translate changeset errors
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
