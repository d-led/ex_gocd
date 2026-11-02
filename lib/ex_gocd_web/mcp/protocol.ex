defmodule ExGoCDWeb.Mcp.Protocol do
  @moduledoc """
  The MCP JSON-RPC surface: `initialize`, `ping`, `tools/list` and `tools/call`.

  Deliberately stateless. The Streamable HTTP transport lets a server hand out an
  `Mcp-Session-Id` and keep state per session; this one does not, so a request
  may land on any connection and no client has to send a header back. What a
  session would hold — which tools exist, whether the client finished
  initializing — cannot differ between requests here, because the tool list is
  compiled and every call is self-contained.

  The HTTP details (status codes, the missing session, methods that are not
  POST, the challenge for an unauthenticated caller) belong to
  `ExGoCDWeb.McpController`; this module decides what a well-formed message
  means.
  """

  alias ExGoCD.Mcp
  alias ExGoCD.Mcp.{Prompts, Resources, Tools}

  @type outcome :: {:reply, map()} | :accepted | {:invalid_request, map()}

  @doc """
  Answers one JSON-RPC message.

  A notification (no `id`) is accepted and answered with nothing: MCP's only
  client notification after initialization is `notifications/initialized`, and a
  server must not answer it.
  """
  @spec handle(term(), map()) :: outcome()
  def handle(%{"jsonrpc" => "2.0", "method" => "notifications/" <> _method}, _ctx) do
    :accepted
  end

  def handle(%{"jsonrpc" => "2.0", "method" => method} = message, ctx) when is_binary(method) do
    case Map.get(message, "id") do
      nil -> :accepted
      id -> dispatch(method, Map.get(message, "params") || %{}, id, ctx)
    end
  end

  def handle(%{"jsonrpc" => _other}, _ctx) do
    {:invalid_request, error(nil, -32_600, "Only JSON-RPC 2.0 messages are supported.")}
  end

  def handle(message, _ctx) when is_map(message) do
    {:invalid_request, error(nil, -32_600, "A JSON-RPC message needs a `method`.")}
  end

  def handle(_message, _ctx) do
    {:invalid_request, error(nil, -32_600, "Batches are not supported; send one message.")}
  end

  defp dispatch("initialize", params, id, _ctx) do
    {:reply,
     result(id, %{
       "protocolVersion" => Mcp.negotiate(version(params)),
       "capabilities" => %{
         "tools" => %{"listChanged" => false},
         "resources" => %{"subscribe" => false, "listChanged" => false},
         "prompts" => %{"listChanged" => false}
       },
       "serverInfo" => Mcp.server_info(),
       "instructions" => Mcp.instructions()
     })}
  end

  defp dispatch("ping", _params, id, _ctx), do: {:reply, result(id, %{})}

  defp dispatch("tools/list", _params, id, _ctx) do
    {:reply, result(id, %{"tools" => Tools.definitions()})}
  end

  defp dispatch("tools/call", params, id, ctx) do
    with {:ok, name} <- tool_name(params),
         {:ok, arguments} <- tool_arguments(params) do
      case Tools.call(name, arguments, ctx) do
        {:ok, %{text: text, structured: structured}} ->
          {:reply, result(id, tool_result(text, structured))}

        {:error, message} ->
          {:reply, result(id, tool_error(message))}

        :unknown_tool ->
          {:reply, error(id, -32_602, "Unknown tool: #{name}")}
      end
    else
      {:error, message} -> {:reply, error(id, -32_602, message)}
    end
  end

  defp dispatch("resources/list", _params, id, _ctx) do
    {:reply, result(id, %{"resources" => Resources.definitions()})}
  end

  defp dispatch("resources/templates/list", _params, id, _ctx) do
    {:reply, result(id, %{"resourceTemplates" => Resources.templates()})}
  end

  defp dispatch("resources/read", params, id, ctx) do
    case resource_uri(params) do
      {:ok, uri} ->
        case Resources.read(uri, ctx) do
          {:ok, content} -> {:reply, result(id, %{"contents" => [content]})}
          # The specification's own code for a URI the server does not publish.
          {:error, message} -> {:reply, error(id, -32_002, message)}
        end

      {:error, message} ->
        {:reply, error(id, -32_602, message)}
    end
  end

  defp dispatch("prompts/list", _params, id, _ctx) do
    {:reply, result(id, %{"prompts" => Prompts.definitions()})}
  end

  defp dispatch("prompts/get", params, id, ctx) do
    with {:ok, name} <- prompt_name(params),
         {:ok, arguments} <- tool_arguments(%{"arguments" => params["arguments"]}),
         {:ok, prompt} <- Prompts.get(name, arguments, ctx) do
      {:reply, result(id, prompt)}
    else
      {:error, message} -> {:reply, error(id, -32_602, message)}
    end
  end

  defp dispatch(method, _params, id, _ctx) do
    {:reply, error(id, -32_601, "Method not found: #{method}")}
  end

  defp version(%{"protocolVersion" => version}), do: version
  defp version(_params), do: nil

  defp tool_name(%{"name" => name}) when is_binary(name) and name != "", do: {:ok, name}
  defp tool_name(_params), do: {:error, "`name` is required."}

  defp resource_uri(%{"uri" => uri}) when is_binary(uri) and uri != "", do: {:ok, uri}
  defp resource_uri(_params), do: {:error, "`uri` is required."}

  defp prompt_name(%{"name" => name}) when is_binary(name) and name != "", do: {:ok, name}
  defp prompt_name(_params), do: {:error, "`name` is required."}

  defp tool_arguments(%{"arguments" => nil}), do: {:ok, %{}}
  defp tool_arguments(%{"arguments" => arguments}) when is_map(arguments), do: {:ok, arguments}
  defp tool_arguments(%{} = params) when not is_map_key(params, "arguments"), do: {:ok, %{}}
  defp tool_arguments(_params), do: {:error, "`arguments` must be a JSON object."}

  defp tool_result(text, structured) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "structuredContent" => structured,
      "isError" => false
    }
  end

  defp tool_error(message) do
    %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}
  end

  defp result(id, payload), do: %{"jsonrpc" => "2.0", "id" => id, "result" => payload}

  defp error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
