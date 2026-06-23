defmodule ExGoCD.Analytics do
  @moduledoc """
  Built-in CI analytics (parity with GoCD Analytics Plugin).
  Pipeline MTTR, pass rate, build/wait times, agent utilization, VSM trends.
  Accessible via LiveView at /analytics — no external tools required.
  """
  import Ecto.Query
  alias ExGoCD.Repo
  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Analytics.AgentTransition
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance}

  def pipeline_analytics(pipeline_name, days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    instances =
      from(pi in PipelineInstance,
        join: p in Pipeline,
        on: pi.pipeline_id == p.id,
        where: p.name == ^pipeline_name and pi.inserted_at >= ^cutoff,
        order_by: [desc: pi.counter]
      )
      |> Repo.all()
      |> Repo.preload(stage_instances: :job_instances)

    if instances == [] do
      %{
        pipeline_name: pipeline_name,
        run_count: 0,
        pass_rate: nil,
        mttr_sec: nil,
        avg_build_time_sec: nil,
        avg_wait_time_sec: nil,
        recent_runs: []
      }
    else
      run_count = length(instances)
      passed = Enum.count(instances, &pipeline_passed?/1)
      pass_rate = Float.round(passed / run_count * 100, 1)
      mttr = calc_mttr(instances)

      %{
        pipeline_name: pipeline_name,
        run_count: run_count,
        pass_rate: pass_rate,
        mttr_sec: mttr,
        avg_build_time_sec: calc_avg_build_time(instances),
        avg_wait_time_sec: calc_avg_wait_time(instances),
        recent_runs: instances |> Enum.take(30) |> Enum.map(&run_summary/1)
      }
    end
  end

  def all_pipelines_analytics(days \\ 7) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    # Simple query: all pipelines with run count in period
    stats =
      from(p in Pipeline,
        left_join: pi in PipelineInstance,
        on: pi.pipeline_id == p.id and pi.inserted_at >= ^cutoff,
        group_by: [p.id, p.name],
        select: %{name: p.name, pipeline_id: p.id, run_count: count(pi.id)}
      )
      |> Repo.all()

    # Fetch latest status per pipeline (separate query to avoid complex SQL)
    latest_statuses = fetch_latest_statuses()

    Enum.map(stats, fn stat ->
      Map.put(stat, :latest_status, Map.get(latest_statuses, stat.name, "Unknown"))
    end)
  end

  defp fetch_latest_statuses do
    # For each pipeline, get the status of the latest run
    rows =
      Repo.query!("""
        SELECT DISTINCT ON (p.name) p.name, si.result as status
        FROM pipelines p
        JOIN pipeline_instances pi ON pi.pipeline_id = p.id
        JOIN stage_instances si ON si.pipeline_instance_id = pi.id
        ORDER BY p.name, pi.counter DESC
      """)

    rows.rows
    |> Enum.map(fn [name, status] -> {name, status || "Unknown"} end)
    |> Enum.into(%{})
  end

  def top_pipelines_by_wait_time(days \\ 7, limit \\ 10) do
    from(p in Pipeline, select: p.name)
    |> Repo.all()
    |> Enum.map(fn name ->
      %{name: name, avg_wait_sec: pipeline_analytics(name, days).avg_wait_time_sec}
    end)
    |> Enum.reject(&is_nil(&1.avg_wait_sec))
    |> Enum.sort_by(& &1.avg_wait_sec, :desc)
    |> Enum.take(limit)
  end

  def agent_analytics(days \\ 7) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    from(r in AgentJobRun,
      where: r.inserted_at >= ^cutoff,
      group_by: r.agent_uuid,
      select: %{
        agent_uuid: r.agent_uuid,
        total_jobs: count(r.id),
        completed: count(r.id) |> filter(r.state in ["Completed", "Passed"]),
        failed: count(r.id) |> filter(r.state == "Failed"),
        cancelled: count(r.id) |> filter(r.state == "Cancelled")
      }
    )
    |> Repo.all()
  end

  def top_agents_by_utilization(days \\ 7, limit \\ 10) do
    agent_analytics(days) |> Enum.sort_by(& &1.total_jobs, :desc) |> Enum.take(limit)
  end

  def vsm_trends(pipeline_name, days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    from(pi in PipelineInstance,
      join: p in Pipeline,
      on: pi.pipeline_id == p.id,
      where: p.name == ^pipeline_name and pi.inserted_at >= ^cutoff,
      order_by: [desc: pi.counter],
      limit: 30
    )
    |> Repo.all()
    |> Repo.preload(stage_instances: :job_instances)
    |> Enum.map(&vsm_run_summary/1)
  end

  defp pipeline_passed?(inst),
    do:
      (inst.stage_instances || []) != [] and
        Enum.all?(inst.stage_instances, &(&1.result == "Passed"))

  defp calc_mttr(instances) do
    sorted = Enum.sort_by(instances, & &1.inserted_at, {:asc, DateTime})

    {recoveries, _} =
      Enum.reduce(sorted, {[], nil}, fn inst, {recs, last_fail} ->
        if pipeline_passed?(inst) && last_fail,
          do: {[DateTime.diff(inst.inserted_at, last_fail) | recs], nil},
          else: {recs, if(!pipeline_passed?(inst), do: inst.inserted_at)}
      end)

    if recoveries == [], do: nil, else: Float.round(Enum.sum(recoveries) / length(recoveries), 1)
  end

  # Convert NaiveDateTime from DB to DateTime for consistent comparisons
  defp to_dt(nil), do: nil
  defp to_dt(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_dt(%DateTime{} = dt), do: dt

  defp calc_avg_build_time(instances) do
    durs =
      for pi <- instances,
          stages = pi.stage_instances || [],
          stages != [],
          first = List.first(stages),
          completed = stages |> Enum.map(&to_dt(&1.completed_at)) |> Enum.reject(&is_nil/1),
          completed != [],
          last = Enum.max(completed, DateTime),
          first.inserted_at,
          do: DateTime.diff(last, first.inserted_at)

    if durs == [], do: nil, else: Float.round(Enum.sum(durs) / length(durs), 1)
  end

  defp calc_avg_wait_time(instances) do
    waits =
      for pi <- instances,
          first = (pi.stage_instances || []) |> List.first(),
          first,
          jobs = first.job_instances || [],
          assigned = jobs |> Enum.map(&to_dt(&1.assigned_at)) |> Enum.reject(&is_nil/1),
          assigned != [],
          first_assigned = Enum.min(assigned, DateTime),
          pi.inserted_at,
          wait = DateTime.diff(first_assigned, pi.inserted_at),
          wait > 0,
          do: wait

    if waits == [], do: nil, else: Float.round(Enum.sum(waits) / length(waits), 1)
  end

  defp run_summary(inst) do
    stages = inst.stage_instances || []
    passed = Enum.all?(stages, &(&1.result == "Passed"))

    status =
      cond do
        passed -> "Passed"
        Enum.any?(stages, &(&1.result == "Failed")) -> "Failed"
        Enum.any?(stages, &(&1.state == "Building")) -> "Building"
        true -> "Unknown"
      end

    first = List.first(stages)
    completed = stages |> Enum.map(&to_dt(&1.completed_at)) |> Enum.reject(&is_nil/1)
    last = if completed != [], do: Enum.max(completed, DateTime)

    %{
      counter: inst.counter,
      label: inst.label,
      status: status,
      build_time_sec:
        first && first.inserted_at && last && DateTime.diff(last, first.inserted_at),
      triggered_at: inst.inserted_at
    }
  end

  defp vsm_run_summary(inst) do
    stages = inst.stage_instances || []

    ss =
      Enum.map(stages, fn si ->
        completed_dt = to_dt(si.completed_at)
        dur = if si.inserted_at && completed_dt, do: DateTime.diff(completed_dt, si.inserted_at)

        %{
          name: si.name,
          state: si.state,
          result: si.result,
          duration_sec: dur,
          job_count: length(si.job_instances || [])
        }
      end)

    first = List.first(stages)
    completed = stages |> Enum.map(&to_dt(&1.completed_at)) |> Enum.reject(&is_nil/1)
    last = if completed != [], do: Enum.max(completed, DateTime)

    %{
      counter: inst.counter,
      label: inst.label,
      triggered_at: inst.inserted_at,
      stage_count: length(stages),
      total_duration_sec:
        first && first.inserted_at && last && DateTime.diff(last, first.inserted_at),
      stages: ss
    }
  end

  # ── Agent State Transitions ───────────────────────────────────────

  @doc """
  Records an agent state change for utilization tracking.
  Called by ExGoCD.Agents.update_agent/2 when state changes.
  """
  def record_agent_transition(agent_uuid, from_state, to_state) do
    %AgentTransition{}
    |> AgentTransition.changeset(%{
      agent_uuid: agent_uuid,
      from_state: from_state,
      to_state: to_state,
      transitioned_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Returns agent state transitions in a time window.
  """
  def agent_transitions(agent_uuid, start_dt, end_dt) do
    Repo.all(
      from t in AgentTransition,
        where: t.agent_uuid == ^agent_uuid,
        where: t.transitioned_at >= ^start_dt,
        where: t.transitioned_at <= ^end_dt,
        order_by: [asc: :transitioned_at]
    )
  end

  @doc """
  Agent utilization ratio (0..1) in the time window.
  """
  def agent_utilization(agent_uuid, start_dt, end_dt) do
    transitions = agent_transitions(agent_uuid, start_dt, end_dt)
    busy_seconds = calc_busy_seconds(transitions, start_dt, end_dt)
    total_seconds = DateTime.diff(end_dt, start_dt)

    if total_seconds > 0 do
      Float.round(busy_seconds / total_seconds, 4)
    else
      0.0
    end
  end

  defp calc_busy_seconds(transitions, window_start, window_end) do
    calc_busy(transitions, window_start, window_end, nil, 0)
  end

  defp calc_busy([], _ws, we, busy_since, acc) do
    if busy_since, do: acc + DateTime.diff(we, busy_since), else: acc
  end

  defp calc_busy([t | rest], ws, we, busy_since, acc) do
    if t.to_state == "Building" do
      calc_busy(rest, ws, we, t.transitioned_at, acc)
    else
      if busy_since do
        new_acc = acc + DateTime.diff(t.transitioned_at, busy_since)
        calc_busy(rest, ws, we, nil, new_acc)
      else
        calc_busy(rest, ws, we, nil, acc)
      end
    end
  end
end
