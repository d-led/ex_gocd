defmodule ExGoCDWeb.PipelineActivityLive do
  @moduledoc """
  LiveView for the Pipeline Activity (History) page.
  Lists all historical runs of a pipeline, their triggering causes, SCM commits, and stage grids.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData
  alias ExGoCD.Pipelines
  alias ExGoCD.Analytics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_tab, "list")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    name = params["pipeline_name"]

    pipeline =
      if use_mock?(name) do
        mock_p = Enum.find(MockData.pipelines(), &(&1.name == name))
        if mock_p, do: %{name: name, group: mock_p.group}, else: nil
      else
        Pipelines.get_pipeline_by_name(name)
      end

    if is_nil(pipeline) do
      {:noreply,
       socket
       |> put_flash(:error, "Pipeline '#{name}' not found.")
       |> redirect(to: "/pipelines")}
    else
      runs = get_pipeline_runs(name)
      stats = if use_mock?(name), do: nil, else: Analytics.pipeline_analytics(name)

      {:noreply,
       socket
       |> assign(:pipeline, pipeline)
       |> assign(:runs, runs)
       |> assign(:stats, stats)
       |> assign(:page_title, "#{name} Activity")
       |> assign(:active_tab, params["tab"] || "list")}
    end
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Helper functions

  defp use_mock?(name) do
    System.get_env("USE_MOCK_DATA") == "true" or not has_db_pipeline?(name)
  end

  defp has_db_pipeline?(name) do
    import Ecto.Query
    ExGoCD.Repo.exists?(from(p in ExGoCD.Pipelines.Pipeline, where: p.name == ^name))
  end

  defp get_pipeline_runs(pipeline_name) do
    if use_mock?(pipeline_name),
      do: get_mock_runs(pipeline_name),
      else: db_pipeline_runs(pipeline_name)
  end

  defp db_pipeline_runs(pipeline_name) do
    case Pipelines.get_pipeline_by_name(pipeline_name) do
      nil ->
        get_mock_runs(pipeline_name)

      p ->
        import Ecto.Query

        config_stage_names = Enum.map(p.stages || [], & &1.name)

        runs =
          ExGoCD.Repo.all(
            from pi in ExGoCD.Pipelines.PipelineInstance,
              where: pi.pipeline_id == ^p.id,
              order_by: [desc: pi.counter],
              preload: [stage_instances: :job_instances]
          )
          |> Enum.map(&map_pipeline_instance(&1, config_stage_names))

        if runs == [], do: get_mock_runs(pipeline_name), else: runs
    end
  end

  defp map_pipeline_instance(pi, config_stage_names) do
    build_cause = pi.build_cause || %{}

    modifications =
      build_cause["materialRevisions"] |> List.wrap() |> Enum.flat_map(&map_modifications/1)

    triggered_by = derive_trigger_reason(build_cause["triggerMessage"], modifications)

    stages =
      pi.stage_instances |> Enum.sort_by(& &1.order_id) |> Enum.map(&map_stage_instance/1)

    # Pad with configured stages that have no instances yet (e.g. only first stage ran)
    filled_stages =
      Enum.map(config_stage_names, fn sname ->
        Enum.find(stages, &(&1.name == sname)) || %{name: sname, status: "NotRun", counter: 0}
      end)

    %{
      counter: pi.counter,
      label: pi.label,
      status: pipeline_instance_status(pi),
      triggered_by: triggered_by,
      last_run: pi.inserted_at || pi.updated_at || DateTime.utc_now(),
      stages: filled_stages,
      modifications: modifications,
      config_changed: Map.has_key?(build_cause, "configSnapshot")
    }
  end

  defp derive_trigger_reason(nil, []), do: "Triggered manually"
  defp derive_trigger_reason(nil, [mod | _]), do: trigger_from_mod(mod)

  defp derive_trigger_reason("Triggered from dashboard", [mod | _]),
    do: trigger_from_mod(mod)

  defp derive_trigger_reason("Triggered from dashboard", []),
    do: "Triggered manually"

  defp derive_trigger_reason(msg, _mods), do: msg

  defp trigger_from_mod(%{user: user}) when user not in ["gocd", "", nil],
    do: "Modified by #{user}"

  defp trigger_from_mod(_), do: "Triggered by SCM change"

  defp map_stage_instance(si) do
    %{name: si.name, status: stage_status(si), counter: si.counter}
  end

  defp map_modifications(rev) do
    fp = fingerprint(rev)

    (rev["modifications"] || [])
    |> Enum.map(fn mod ->
      revision = mod["revision"] || "unknown"
      raw_comment = mod["comment"] || ""

      comment = clean_comment(raw_comment, revision)

      %{
        revision: revision,
        user: mod["username"] || "anonymous",
        comment: comment,
        fingerprint: fp
      }
    end)
  end

  defp clean_comment("", _revision), do: nil
  defp clean_comment(comment, _revision) when byte_size(comment) < 3, do: comment

  defp clean_comment(comment, _revision) do
    if String.starts_with?(comment, "git ls-remote") or
         comment == "Triggered commit" or
         comment == "Auto-detected update via git ls-remote" do
      nil
    else
      comment
    end
  end

  defp stage_status(si) do
    case {si.state, si.result} do
      {"Awaiting", _} -> "Awaiting"
      {"Building", _} -> "Building"
      {"Completed", "Passed"} -> "Passed"
      {"Completed", "Failed"} -> "Failed"
      {"Completed", "Cancelled"} -> "Cancelled"
      _ -> "NotRun"
    end
  end

  defp pipeline_instance_status(pi) do
    Pipelines.pipeline_instance_status(pi)
  end

  defp fingerprint(rev) do
    type = rev["type"] || "git"
    url = rev["url"] || ""
    branch = rev["branch"] || ""

    :crypto.hash(:sha256, "#{type}-#{url}-#{branch}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp get_mock_runs(pipeline_name) do
    mock_pipeline = Enum.find(MockData.pipelines(), &(&1.name == pipeline_name))
    base_counter = if mock_pipeline, do: mock_pipeline.counter, else: 145

    [
      %{
        counter: base_counter,
        label: to_string(base_counter),
        status: if(mock_pipeline, do: mock_pipeline.status, else: "Passed"),
        triggered_by:
          if(mock_pipeline, do: mock_pipeline.triggered_by, else: "Triggered by dmitry"),
        last_run: ~U[2026-06-11 12:00:00Z],
        stages:
          if mock_pipeline do
            Enum.map(mock_pipeline.stages, &%{name: &1.name, status: &1.status, counter: 1})
          else
            [
              %{name: "compile", status: "Passed", counter: 1},
              %{name: "test", status: "Passed", counter: 1}
            ]
          end,
        modifications: [
          %{
            revision: "05172d07f4f4a0765243628b94f6840f8dc5411a",
            user: "Dmitry Ledentsov <dmlled@yahoo.com>",
            comment: "upgrade actions and fix compilation warnings",
            fingerprint: "8d78bc9f6c661806"
          }
        ]
      },
      %{
        counter: base_counter - 1,
        label: to_string(base_counter - 1),
        status: "Failed",
        triggered_by: "Triggered by dmitry",
        last_run: ~U[2026-06-11 10:30:00Z],
        stages:
          if mock_pipeline do
            Enum.map(
              mock_pipeline.stages,
              &%{
                name: &1.name,
                status: if(&1.name == "test", do: "Failed", else: "Passed"),
                counter: 1
              }
            )
          else
            [
              %{name: "compile", status: "Passed", counter: 1},
              %{name: "test", status: "Failed", counter: 1}
            ]
          end,
        modifications: [
          %{
            revision: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0",
            user: "Dmitry Ledentsov <dmlled@yahoo.com>",
            comment: "add test suite support",
            fingerprint: "8d78bc9f6c661806"
          }
        ]
      },
      %{
        counter: base_counter - 2,
        label: to_string(base_counter - 2),
        status: "Passed",
        triggered_by: "Triggered manually by admin",
        last_run: ~U[2026-06-11 08:15:00Z],
        stages:
          if mock_pipeline do
            Enum.map(mock_pipeline.stages, &%{name: &1.name, status: "Passed", counter: 1})
          else
            [
              %{name: "compile", status: "Passed", counter: 1},
              %{name: "test", status: "Passed", counter: 1}
            ]
          end,
        modifications: [
          %{
            revision: "f0e1d2c3b4a5968776655443322110abcdef0123",
            user: "exgocd-admin <admin@exgocd.local>",
            comment: "initial configuration setup",
            fingerprint: "8d78bc9f6c661806"
          }
        ]
      }
    ]
  end

  defp format_local_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp stage_status_class(status) do
    case status do
      "Passed" -> "bg-[#5cb85c] hover:bg-[#4cae4c]"
      "Failed" -> "bg-[#d9534f] hover:bg-[#d43f3a]"
      "Building" -> "bg-[#5bc0de] hover:bg-[#46b8da]"
      "Cancelled" -> "bg-[#f0ad4e] hover:bg-[#eea236]"
      "Awaiting" -> "bg-[#e7eef0] border border-[#b6cdd2] text-gray-700 hover:bg-gray-100"
      _ -> "bg-gray-300 hover:bg-gray-400"
    end
  end

  defp run_status_border(status) do
    case status do
      "Passed" -> "border-l-4 border-l-[#5cb85c]"
      "Failed" -> "border-l-4 border-l-[#d9534f]"
      "Building" -> "border-l-4 border-l-[#5bc0de]"
      _ -> "border-l-4 border-l-gray-300"
    end
  end

  defp run_status_dot("Passed"), do: "bg-[#5cb85c]"
  defp run_status_dot("Failed"), do: "bg-[#d9534f]"
  defp run_status_dot("Building"), do: "bg-[#5bc0de]"
  defp run_status_dot(_), do: "bg-gray-300"

  defp format_duration_short(seconds) when is_number(seconds) do
    mins = div(round(seconds), 60)
    secs = rem(round(seconds), 60)
    if mins > 0, do: "#{mins}m #{secs}s", else: "#{secs}s"
  end

  defp format_duration_short(_), do: "—"

  # ── Timeline/Gantt chart component ──────────────────────────────────────

  defp timeline_chart(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-bold text-gray-800 mb-3 flex items-center gap-2">
        <i class="fa-solid fa-chart-gantt text-[#2d6ca2]"></i> Pipeline Run Timeline
      </h3>

      <%!-- Legend --%>
      <div class="flex items-center gap-4 mb-5 text-[10px] text-gray-500">
        <span class="flex items-center gap-1"><span class="w-2.5 h-2.5 rounded bg-[#5cb85c]"></span> Passed</span>
        <span class="flex items-center gap-1"><span class="w-2.5 h-2.5 rounded bg-[#d9534f]"></span> Failed</span>
        <span class="flex items-center gap-1"><span class="w-2.5 h-2.5 rounded bg-[#5bc0de]"></span> Building</span>
      </div>

      <%= if @runs == [] do %>
        <p class="text-gray-400 text-xs">No pipeline runs to display.</p>
      <% else %>
        <% timestamps = Enum.map(@runs, & &1.last_run) |> Enum.reject(&is_nil/1) %>
        <% min_ts = if timestamps != [], do: Enum.min(timestamps, DateTime), else: DateTime.utc_now() %>
        <% max_ts = if timestamps != [], do: Enum.max(timestamps, DateTime), else: DateTime.utc_now() %>
        <% span = max(max(DateTime.diff(max_ts, min_ts, :second), 1), 60) %>

        <div class="overflow-x-auto">
          <div class="min-w-[600px]">
            <%!-- Time axis header --%>
            <div class="flex border-b border-gray-200 pb-2 mb-3 text-[9px] text-gray-400 font-mono">
              <span class="w-16 shrink-0">#</span>
              <span class="w-24 shrink-0 text-right"><%= Calendar.strftime(min_ts, "%H:%M") %></span>
              <span class="flex-1 text-center"><%= Calendar.strftime(DateTime.add(min_ts, div(span, 2), :second), "%H:%M") %></span>
              <span class="w-24 shrink-0 text-right"><%= Calendar.strftime(max_ts, "%H:%M") %></span>
            </div>

            <div class="space-y-2">
              <%= for run <- Enum.reverse(@runs) do %>
                <% dur = timeline_run_duration(run) %>
                <% left_pct = if span > 0, do: Float.round(max(DateTime.diff(run.last_run || min_ts, min_ts, :second), 0) / span * 100, 1), else: 0 %>
                <% width_pct = if span > 0 and dur > 0, do: Float.round(dur / span * 100, 1), else: 0.5 %>

                <div class="flex items-center gap-2 text-xs">
                  <%!-- Counter label --%>
                  <.link
                    navigate={~p"/pipelines/value_stream_map/#{@pipeline_name}/#{run.counter}"}
                    class="w-16 shrink-0 font-mono font-extrabold text-gray-900 text-right hover:text-[#2d6ca2]"
                  >
                    ##{run.label}
                  </.link>

                  <%!-- Gantt bar --%>
                  <div class="flex-1 h-6 relative">
                    <div
                      class={"absolute top-0 h-full rounded-sm opacity-80 hover:opacity-100 transition-opacity cursor-pointer " <> timeline_bar_color(run.status)}
                      style={"left:#{left_pct}%;width:#{max(width_pct, 1)}%"}
                      title={"##{run.counter}: #{run.status} — #{timeline_run_duration(run)}s (triggered #{Calendar.strftime(run.last_run, "%Y-%m-%d %H:%M")})"}
                    >
                    </div>
                  </div>

                  <%!-- Duration + status label --%>
                  <span class="w-24 shrink-0 text-right text-gray-500 tabular-nums">
                    {format_duration_short(dur)}
                  </span>
                  <span class={[
                    "w-14 shrink-0 text-center text-[9px] font-bold rounded px-1 py-0.5",
                    run.status == "Passed" && "bg-green-100 text-green-700",
                    run.status == "Failed" && "bg-red-100 text-red-700",
                    run.status == "Building" && "bg-blue-100 text-blue-700",
                    run.status not in ["Passed", "Failed", "Building"] && "bg-gray-100 text-gray-500"
                  ]}>
                    {run.status}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp timeline_run_duration(run) do
    if run[:last_run] do
      # Approximate: use trigger time as start, and assume ~120s if no explicit duration
      dur = if run[:duration], do: run[:duration], else: 120
      dur
    else
      0
    end
  end

  defp timeline_bar_color("Passed"), do: "bg-[#5cb85c]"
  defp timeline_bar_color("Failed"), do: "bg-[#d9534f]"
  defp timeline_bar_color("Building"), do: "bg-[#5bc0de]"
  defp timeline_bar_color(_), do: "bg-gray-400"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pipeline-activity-page px-8 py-8 bg-[#f4f8f9] min-h-screen">
      <div class="page-header flex justify-between items-center border-b border-gray-200 pb-4 mb-6">
        <div class="flex flex-col">
          <div class="flex items-center gap-2 text-xs text-gray-500 font-mono font-bold uppercase tracking-wider">
            <.link navigate={~p"/pipelines"} class="text-[#2d6ca2] hover:underline">Pipelines</.link>
            <span>/</span>
            <span>{@pipeline.group}</span>
          </div>
          <h1 class="text-2xl font-extrabold text-gray-950 mt-1 flex items-center gap-2">
            {@pipeline.name}
            <span class="text-sm font-semibold text-gray-500 font-mono">History</span>
          </h1>
        </div>
      </div>

      <%= if @stats && @stats.run_count > 0 do %>
        <div class="stats-bar flex flex-wrap gap-4 mb-4">
          <div class="bg-white border border-gray-200 rounded shadow-sm px-4 py-3 flex flex-col gap-0.5 min-w-[120px]">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              Pass Rate
            </span>
            <span class={[
              "text-lg font-extrabold font-mono",
              if(@stats.pass_rate >= 80,
                do: "text-green-600",
                else: if(@stats.pass_rate >= 50, do: "text-amber-600", else: "text-red-600")
              )
            ]}>
              {@stats.pass_rate}%
            </span>
            <span class="text-[10px] text-gray-400">last {@stats.run_count} runs</span>
          </div>
          <div class="bg-white border border-gray-200 rounded shadow-sm px-4 py-3 flex flex-col gap-0.5 min-w-[120px]">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              MTTR
            </span>
            <span class="text-lg font-extrabold font-mono text-gray-800">
              {if @stats.mttr_sec, do: format_duration_short(@stats.mttr_sec), else: "—"}
            </span>
            <span class="text-[10px] text-gray-400">mean time to recover</span>
          </div>
          <div class="bg-white border border-gray-200 rounded shadow-sm px-4 py-3 flex flex-col gap-0.5 min-w-[120px]">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              Avg Build
            </span>
            <span class="text-lg font-extrabold font-mono text-gray-800">
              {if @stats.avg_build_time_sec,
                do: format_duration_short(@stats.avg_build_time_sec),
                else: "—"}
            </span>
            <span class="text-[10px] text-gray-400">per run</span>
          </div>
          <div class="bg-white border border-gray-200 rounded shadow-sm px-4 py-3 flex flex-col gap-0.5 min-w-[120px]">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              Avg Wait
            </span>
            <span class="text-lg font-extrabold font-mono text-gray-800">
              {if @stats.avg_wait_time_sec,
                do: format_duration_short(@stats.avg_wait_time_sec),
                else: "—"}
            </span>
            <span class="text-[10px] text-gray-400">before agent picks up</span>
          </div>
        </div>
      <% end %>

      <%!-- Tab bar: List | Timeline --%>
      <nav class="flex border-b border-gray-200 mb-4" aria-label="View tabs">
        <button
          phx-click="select_tab"
          phx-value-tab="list"
          class={"px-4 py-2.5 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "list", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
        >
          <i class="fa-solid fa-list mr-1.5"></i> List
        </button>
        <button
          phx-click="select_tab"
          phx-value-tab="timeline"
          class={"px-4 py-2.5 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "timeline", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
        >
          <i class="fa-solid fa-chart-gantt mr-1.5"></i> Timeline
        </button>
      </nav>

      <%= if @active_tab == "timeline" do %>
        <div class="bg-white border border-gray-200 rounded shadow-sm p-6">
          <.timeline_chart runs={@runs} pipeline_name={@pipeline.name} />
        </div>
      <% else %>
        <div class="activity-container flex flex-col gap-2">
          <%= for run <- @runs do %>
          <div class={"flex bg-white border border-gray-200 rounded shadow-sm hover:shadow-md transition-shadow " <> run_status_border(run.status)}>
            <!-- Row: counter, VSM, revision, trigger, status, stages — all one line -->
            <div class="flex-grow min-w-0 px-3 py-2 flex flex-col gap-1">
              <!-- Top line: counter + VSM + revisions + trigger time + status -->
              <div class="flex items-center gap-2 flex-wrap text-xs">
                <span class="font-mono font-extrabold text-gray-900">#{run.label}</span>
                <.link
                  navigate={~p"/pipelines/value_stream_map/#{@pipeline.name}/#{run.counter}"}
                  class="text-[#2d6ca2] hover:underline font-bold text-[10px]"
                >
                  VSM
                </.link>

                <%= for mod <- run.modifications do %>
                  <.link
                    navigate={~p"/materials/value_stream_map/#{mod.fingerprint}/#{mod.revision}"}
                    class="font-mono text-cyan-600 hover:underline"
                  >
                    {String.slice(mod.revision, 0, 8)}
                  </.link>
                <% end %>

                <span class="text-gray-400" title={format_local_time(run.last_run)}>
                  {format_local_time(run.last_run)}
                </span>

                <span class="text-gray-500">{run.triggered_by}</span>

                <span
                  class={"inline-block w-2 h-2 rounded-full shrink-0 " <> run_status_dot(run.status)}
                  title={run.status}
                >
                </span>
                <span class="text-gray-500 font-medium">{run.status}</span>

                <%= if Map.get(run, :config_changed) do %>
                  <.link
                    navigate={~p"/pipelines/#{@pipeline.name}/#{run.counter}/config_diff"}
                    class="text-purple-500 hover:text-purple-700"
                    title="Config changed since previous run — click to view diff"
                  >
                    <i class="fa fa-cog"></i>
                  </.link>
                <% end %>
              </div>
              
    <!-- Commit messages: every material, full text, no clipping -->
              <%= if Enum.any?(run.modifications, & &1.comment) do %>
                <div class="flex flex-col gap-0.5">
                  <%= for mod <- run.modifications, mod.comment do %>
                    <div class="text-[11px] text-gray-500 italic break-all leading-snug">
                      {mod.comment}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
            
    <!-- Stage pipeline: compact horizontal strip -->
            <div class="flex-shrink-0 flex items-center gap-1.5 px-3 py-2 border-l border-gray-100">
              <%= for {stage, idx} <- Enum.with_index(run.stages) do %>
                <%= if idx > 0 do %>
                  <span class="text-gray-300 text-xs">&rarr;</span>
                <% end %>
                <.link
                  navigate={
                    ~p"/pipelines/#{@pipeline.name}/#{run.counter}/#{stage.name}/#{stage.counter}"
                  }
                  class={"px-2 py-1 rounded text-white font-mono font-bold text-[10px] hover:scale-105 transition-transform shadow-sm " <> stage_status_class(stage.status)}
                  title={"#{stage.name} — #{stage.status}"}
                >
                  {stage.name}
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      <% end %>
    </div>
    """
  end
end
