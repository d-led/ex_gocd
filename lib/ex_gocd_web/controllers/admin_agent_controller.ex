defmodule ExGoCDWeb.AdminAgentController do
  @moduledoc """
  Controller for original GoCD agent registration endpoints.

  Implements the legacy `/admin/agent` endpoints for backward compatibility
  with existing GoCD agents.

  Original GoCD endpoints:
  - POST /admin/agent - Form-based agent registration
  - GET /admin/agent/token - Get registration token for agent
  - GET /admin/agent/root_certificate - Get server CA certificate (HTTPS only)
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

    # Map form parameters to agent attributes
    attrs = %{
      "uuid" => params["uuid"],
      "hostname" => params["hostname"] || params["agentAutoRegisterHostname"],
      "ipaddress" => params["ipAddress"],
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

    # Validate required fields
    unless attrs["uuid"] && attrs["hostname"] do
      Logger.error("Missing required fields: uuid=#{attrs["uuid"]}, hostname=#{attrs["hostname"]}")

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

    # Generate a simple token (in production, this would be more secure)
    token = "agent-token-#{uuid}-#{:os.system_time(:millisecond)}"

    conn
    |> put_resp_content_type("text/plain")
    |> text(token)
  end

  def token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing uuid parameter"})
  end

  @doc """
  GET /admin/agent/root_certificate

  Returns the server's root CA certificate for TLS connections.
  Only relevant for HTTPS deployments.
  """
  def root_certificate(conn, _params) do
    Logger.info("Root certificate request")

    # For development with HTTP, return a placeholder
    # In production with HTTPS, this would return the actual CA certificate
    cert = """
    -----BEGIN CERTIFICATE-----
    # Development placeholder - not using TLS
    # In production, this would be the actual server CA certificate
    -----END CERTIFICATE-----
    """

    conn
    |> put_resp_content_type("text/plain")
    |> text(cert)
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
