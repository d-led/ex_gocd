defmodule ExGoCDWeb.LowSpaceBanner do
  @moduledoc """
  Banner component showing agents low on disk space.
  Threshold configurable via `AGENT_LOW_SPACE_THRESHOLD_MB` (default 1024).
  Shows first 3 agent names, then "and N more" with a link to the agents page.
  """
  use Phoenix.Component

  alias ExGoCD.Agents

  def low_space_banner(assigns) do
    assigns = assign(assigns, :low_agents, Agents.low_space_agents())

    ~H"""
    <%= if @low_agents != [] do %>
      <div class="bg-amber-50 border-b border-amber-200 px-4 py-2 text-sm">
        <div class="flex items-center gap-2 flex-wrap">
          <svg
            class="w-4 h-4 text-amber-600 shrink-0"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
            />
          </svg>
          <span class="font-semibold text-amber-800">
            {length(@low_agents)} agent(s) low on disk space:
          </span>
          <span class="text-amber-700">
            <%= for {agent, i} <- Enum.with_index(@low_agents) do %>
              <%= if i < 3 do %>
                <a
                  href={"/agents/#{agent.uuid}/job_run_history"}
                  class="font-mono text-amber-800 hover:underline"
                >
                  {agent.hostname}
                </a>
                <span class="text-amber-500 font-mono">
                  ({format_bytes(agent.free_space)} free)
                </span>
                {if i < min(2, length(@low_agents) - 1), do: ", "}
              <% end %>
            <% end %>
            <%= if length(@low_agents) > 3 do %>
              <span class="text-amber-600">
                and {length(@low_agents) - 3} more —
                <a href="/agents" class="font-semibold text-amber-800 hover:underline">
                  view all agents
                </a>
              </span>
            <% end %>
          </span>
        </div>
      </div>
    <% end %>
    """
  end

  defp format_bytes(nil), do: "unknown"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{div(bytes, 1024)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"
end
