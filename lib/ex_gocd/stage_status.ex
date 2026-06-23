defmodule ExGoCD.StageStatus do
  @moduledoc """
  Strongly-typed stage/job status constants. Replaces raw strings throughout the codebase.

  GoCD parity: mirrors `com.thoughtworks.go.domain.StageState` and `JobState`.
  """

  # ── Lifecycle States ──────────────────────────────────────────────────
  @state_scheduled "Scheduled"
  @state_assigned "Assigned"
  @state_preparing "Preparing"
  @state_building "Building"
  @state_completed "Completed"
  @state_awaiting "Awaiting"
  @state_cancelled "Cancelled"
  @state_failed "Failed"

  # ── Result States ─────────────────────────────────────────────────────
  @result_passed "Passed"
  @result_failed "Failed"
  @result_cancelled "Cancelled"
  @result_unknown "Unknown"

  # ── VSM Display States ────────────────────────────────────────────────
  @vsm_not_yet_run "Not Yet Run"

  # ── Collections ───────────────────────────────────────────────────────
  @terminal_states [@result_passed, @result_failed, @result_cancelled, @state_cancelled]

  # ── Guards (compile-time) ─────────────────────────────────────────────
  defguard is_passed(s) when s == @result_passed or s == @state_completed
  defguard is_failed(s) when s == @result_failed or s == @state_failed
  defguard is_building(s) when s == @state_building
  defguard is_cancelled(s) when s == @result_cancelled or s == @state_cancelled
  defguard is_awaiting(s) when s == @state_awaiting
  defguard is_not_yet_run(s) when s == @vsm_not_yet_run
  defguard is_unknown(s) when s == @result_unknown
  defguard is_terminal(s) when s in @terminal_states

  # ── Public API ────────────────────────────────────────────────────────

  @doc "Returns the CSS background class for a VSM stage square."
  @spec stage_bg(String.t()) :: String.t()
  def stage_bg(@result_passed), do: "bg-[#5cb85c]"
  def stage_bg(@state_completed), do: "bg-[#5cb85c]"
  def stage_bg(@result_failed), do: "bg-[#d9534f]"
  def stage_bg(@state_building), do: "bg-[#5bc0de]"
  def stage_bg(@state_scheduled), do: "bg-[#b6cdd2]"
  def stage_bg(@state_assigned), do: "bg-[#b6cdd2]"
  def stage_bg(@state_preparing), do: "bg-[#f0ad4e]"
  def stage_bg(@result_cancelled), do: "bg-[#f0ad4e]"
  def stage_bg(@state_awaiting), do: "bg-[#e7eef0] border border-[#b6cdd2]"
  def stage_bg(@vsm_not_yet_run), do: "bg-[#e7eef0] border border-dashed border-[#b6cdd2]"
  def stage_bg(@result_unknown), do: "bg-[#e7eef0] border border-dashed border-[#b6cdd2]"
  def stage_bg(_), do: "bg-gray-300"

  @doc "Returns the CSS border class for a VSM pipeline node."
  @spec node_border(String.t() | nil) :: String.t()
  def node_border(@result_passed), do: "border-[#5cb85c] border-2"
  def node_border(@result_failed), do: "border-[#d9534f] border-2"
  def node_border(@state_building), do: "border-[#5bc0de] border-2"
  def node_border(@result_cancelled), do: "border-[#f0ad4e] border-2"
  def node_border(@state_awaiting), do: "border-[#b6cdd2] border-2"
  def node_border(@vsm_not_yet_run), do: "border-[#b6cdd2] border-2"
  def node_border(@result_unknown), do: "border-[#b6cdd2] border-2"
  def node_border(nil), do: "border-[#2fa8b6]"
  def node_border(_), do: "border-[#2fa8b6]"

  @doc "Returns the CSS badge class for a VSM pipeline node status badge."
  @spec node_badge(String.t()) :: String.t()
  def node_badge(@result_passed), do: "bg-[#5cb85c] text-white"
  def node_badge(@result_failed), do: "bg-[#d9534f] text-white"
  def node_badge(@state_building), do: "bg-[#5bc0de] text-white"
  def node_badge(@result_cancelled), do: "bg-[#f0ad4e] text-white"
  def node_badge(@state_awaiting), do: "bg-[#e7eef0] text-gray-600"
  def node_badge(@vsm_not_yet_run), do: "bg-[#e7eef0] text-gray-600"
  def node_badge(@result_unknown), do: "bg-[#e7eef0] text-gray-600"
  def node_badge(_), do: "bg-gray-300 text-gray-600"

  @doc """
  Determines the aggregate VSM node status from a list of individual stage statuses.
  Returns the dominant status or nil for all-unrun.
  """
  @spec pipeline_status([String.t()]) :: String.t()
  def pipeline_status([]), do: @vsm_not_yet_run
  def pipeline_status(statuses) do
    cond do
      Enum.any?(statuses, &is_failed/1) -> @result_failed
      Enum.any?(statuses, &is_building/1) -> @state_building
      Enum.any?(statuses, &is_cancelled/1) -> @result_cancelled
      Enum.all?(statuses, &is_passed/1) -> @result_passed
      Enum.any?(statuses, &is_awaiting/1) -> @state_awaiting
      Enum.all?(statuses, &(is_not_yet_run(&1) or is_unknown(&1))) -> @vsm_not_yet_run
      true -> @result_unknown
    end
  end

  @doc "Returns the display status from a StageInstance, preferring result over state."
  @spec from_instance(map()) :: String.t()
  def from_instance(%{result: r}) when is_binary(r) and r != @result_unknown, do: r
  def from_instance(%{result: _}), do: @state_completed
  def from_instance(%{state: s}) when is_binary(s), do: s
  def from_instance(_), do: @result_unknown
end
