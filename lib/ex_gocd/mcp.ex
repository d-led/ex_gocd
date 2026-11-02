defmodule ExGoCD.Mcp do
  @moduledoc """
  The Model Context Protocol server: its identity, the protocol revisions it
  speaks, and what it tells a client before the client picks a tool.

  What a message *means* is `ExGoCDWeb.Mcp.Protocol`; how it travels is
  `ExGoCDWeb.McpController`; the tools are `ExGoCD.Mcp.Tools` and the modules
  under it. This module holds what all of them agree on, so a version or a
  name is written once.

  What the server is for: an assistant that has to answer questions about a
  running GoCD server — what is configured, what ran, what is running now, why
  nothing is running, and what the numbers say — with the same answers the
  dashboard, the API and the admin pages give, because the tools call the same
  contexts those pages call.
  """

  # Newest first. `initialize` answers with what the client asked for when this
  # server speaks it, and with the first entry when it does not, which is what
  # the lifecycle section of the specification asks a server to do.
  @protocol_versions ~w(2025-06-18 2025-03-26 2024-11-05)

  @doc "Protocol revisions this server can talk."
  @spec protocol_versions() :: [String.t()]
  def protocol_versions, do: @protocol_versions

  @doc "The newest revision, used when the client asks for one we do not know."
  @spec latest_protocol_version() :: String.t()
  def latest_protocol_version, do: hd(@protocol_versions)

  @doc "Whether this server speaks a revision."
  @spec protocol_version?(term()) :: boolean()
  def protocol_version?(version) when is_binary(version), do: version in @protocol_versions
  def protocol_version?(_version), do: false

  @doc "The revision to answer an `initialize` with."
  @spec negotiate(term()) :: String.t()
  def negotiate(requested) do
    if protocol_version?(requested), do: requested, else: latest_protocol_version()
  end

  @doc "The `serverInfo` object of an `initialize` result."
  @spec server_info() :: map()
  def server_info do
    %{"name" => "gocd-mcp", "title" => "GoCD server", "version" => version()}
  end

  @doc """
  What a client is told before it picks a tool.

  Short on purpose — a model pays for every token and the tool descriptions
  already say what each tool does. This says the four things a model cannot
  infer: that every answer comes from this server's own data, which identifier
  each family of tools takes, that writes are permission-checked and audited the
  way the web UI's are, and that a pipeline is addressed by name while a run is
  addressed by name *and* counter.
  """
  @spec instructions() :: String.t()
  def instructions do
    """
    This server answers questions about the GoCD instance it is running in — its \
    configuration, its runs, its agents and its numbers — and can act on them.

    Answers come from the server, not from a copy: the tools call the same \
    contexts the dashboard, the JSON API and the admin pages call. So "the \
    numbers" here are this instance's, and where they disagree with a screenshot \
    or a memory of GoCD's Java behaviour, say so rather than averaging them.

    Naming: a pipeline is addressed by `name`; one run of it by `name` and \
    `counter`; a stage by pipeline, counter, stage name and stage counter; a job \
    by those plus the job name. `gocd_pipeline_status` and `gocd_pipeline_instance` \
    say what exists before you act. Agents are addressed by `uuid` \
    (`gocd_list_agents` gives them).

    Writing: `gocd_trigger_pipeline`, `gocd_set_pipeline_paused`, \
    `gocd_approve_stage`, `gocd_cancel_stage`, `gocd_rerun_failed_jobs`, \
    `gocd_schedule_job`, `gocd_update_agent` and `gocd_kill_agent_tasks` change \
    the server. They check the same permissions the web UI checks, and the ones \
    that stop or discard work ask for `confirm: true` first; a call without it \
    answers what would change and changes nothing. `gocd_audit_log` shows who \
    did what.

    Reading first: `gocd_server_info` for the state of the deployment, \
    `gocd_dashboard` for every pipeline's latest status, `gocd_pipeline_analytics` \
    and `gocd_agent_analytics` for trends rather than snapshots, \
    `gocd_queue` when work is not moving, and `gocd_job_console` when a run \
    failed.

    Three things are not tools. Documents — the dashboard, the configuration XML, \
    the audit trail, one pipeline's configuration — are resources under `gocd://`, \
    listed by `resources/list`. The workflows worth following in order (diagnose a \
    failed pipeline, why nothing is running, what changed, how the fleet is doing) \
    are prompts, listed by `prompts/list`. Both read as you, with your permissions.
    """
  end

  defp version do
    case Application.spec(:ex_gocd, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end
end
