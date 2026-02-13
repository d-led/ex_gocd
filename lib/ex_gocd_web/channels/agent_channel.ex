# Copyright 2026 ex_gocd
# Phoenix channel for GoCD agents over WebSocket.
# Tracks presence on join (connection loss is detected by Presence when process exits).
# Assignment of test jobs is done via AgentRegistry, not here.

defmodule ExGoCDWeb.AgentChannel do
  use Phoenix.Channel

  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentRegistry
  alias ExGoCD.Scheduler
  alias ExGoCDWeb.AgentPresence

  @agent_topic_prefix "agent:"
  @presence_topic "agent"

  @doc """
  Delegates to AgentRegistry. Returns :ok or {:error, reason}.
  """
  def run_test_job(agent_uuid), do: AgentRegistry.request_test_job(agent_uuid)

  @impl true
  def join("agent", payload, socket) do
    uuid = get_uuid(payload)
    normalized = normalize_join_payload(payload)

    result =
      case Agents.touch_agent_on_heartbeat(uuid, normalized) do
        :ok ->
          socket = assign_agent_socket(socket, uuid)
          socket = maybe_assign_cookie_to_send(socket, uuid)
          send(self(), :after_join)
          {:ok, socket}

        {:error, :cookie_mismatch} ->
          # Allow join so we can push setCookie; agent will send cookie on next ping
          socket = assign_agent_socket(socket, uuid)
          socket = maybe_assign_cookie_to_send(socket, uuid)
          send(self(), :after_join)
          {:ok, socket}

        {:error, :not_found} ->
          socket = assign_agent_socket(socket, uuid)
          send(self(), :after_join)
          {:ok, socket}
      end

    result
  end

  @impl true
  def handle_info(:after_join, socket) do
    if cookie = socket.assigns[:cookie_to_send] do
      push(socket, "setCookie", cookie)
    end

    {:noreply, socket}
  end

  def handle_info({:build, payload}, socket) do
    push(socket, "build", payload)
    {:noreply, socket}
  end

  defp assign_agent_socket(socket, uuid) do
    socket
    |> assign(:agent_uuid, uuid)
    |> assign(:agent_topic, @agent_topic_prefix <> uuid)
    |> then(fn s ->
      Phoenix.PubSub.subscribe(ExGoCD.PubSub, s.assigns.agent_topic)
      AgentPresence.track(self(), @presence_topic, uuid, %{})
      s
    end)
  end

  defp normalize_join_payload(%{"identifier" => data}) when is_map(data), do: data
  defp normalize_join_payload(payload), do: payload

  # Store cookie in assigns so we can push in handle_info(:after_join); push/3 is not allowed during join.
  defp maybe_assign_cookie_to_send(socket, uuid) do
    case Agents.get_agent_by_uuid(uuid) do
      %{cookie: cookie} when is_binary(cookie) and cookie != "" ->
        assign(socket, :cookie_to_send, cookie)

      _ ->
        socket
    end
  end

  # Payload can be: top-level uuid; or full AgentRuntimeInfo with identifier.uuid (on join/ping).
  defp get_uuid(payload) when is_map(payload) do
    cond do
      uuid = payload["uuid"] -> uuid
      id = payload["identifier"] ->
        if is_map(id) do
          id["uuid"] || id["agent_uuid"] || nested_uuid(id["identifier"])
        else
          nil
        end
      true -> nil
    end || "unknown"
  end
  defp get_uuid(_), do: "unknown"

  defp nested_uuid(nil), do: nil
  defp nested_uuid(id) when is_map(id), do: id["uuid"] || id["agent_uuid"]
  defp nested_uuid(_), do: nil

  @impl true
  def handle_in("ping", payload, socket) do
    # Ping may have runtime info at top level, under "data" (Go client), or agentRuntimeInfo.
    runtime_info = payload["agentRuntimeInfo"] || payload["data"] || payload
    _ = Agents.touch_agent_on_heartbeat(socket.assigns.agent_uuid, runtime_info)
    # GoCD-style: when agent reports Idle, try to assign work from the scheduler queue.
    if (runtime_info["runtimeStatus"] || get_in(payload, ["agentRuntimeInfo", "runtimeStatus"])) == "Idle" do
      _ = Scheduler.try_assign_work(socket.assigns.agent_uuid)
    end
    {:reply, {:ok, %{}}, socket}
  end

  @impl true
  def handle_in("reportCurrentStatus", payload, socket) do
    apply_report(socket.assigns.agent_uuid, payload, nil)
    {:noreply, socket}
  end

  @impl true
  def handle_in("reportCompleting", payload, socket) do
    apply_report(socket.assigns.agent_uuid, payload, nil)
    {:noreply, socket}
  end

  @impl true
  def handle_in("reportCompleted", payload, socket) do
    result = payload["result"]
    apply_report(socket.assigns.agent_uuid, payload, result)
    {:noreply, socket}
  end

  defp apply_report(agent_uuid, payload, result) do
    build_id = payload["buildId"]
    job_state = payload["jobState"]
    if build_id && job_state, do: AgentJobRuns.report_status(agent_uuid, build_id, job_state, result)
    # So the UI shows Building/Idle immediately without waiting for the next ping
    if runtime_status = get_in(payload, ["agentRuntimeInfo", "runtimeStatus"]) do
      Agents.update_agent_runtime_state(agent_uuid, runtime_status)
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # When the agent WebSocket disconnects (process exits), Presence auto-removes the agent.
    # Mark DB state as LostContact so the UI shows it immediately (same idea as GoCD's
    # AgentInstance.lostContact() / refresh() when lastHeardTime times out).
    if uuid = socket.assigns[:agent_uuid] do
      Agents.mark_lost_contact(uuid)
    end
    :ok
  end
end
