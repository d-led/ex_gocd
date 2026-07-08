defmodule ExGoCDWeb.FeedsController do
  @moduledoc """
  Atom/RSS feeds endpoint. Renders pipeline status as a feed
  compatible with CI monitoring tools (CCMenu, CCTray, etc.).
  """
  use ExGoCDWeb, :controller

  require Ecto.Query
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.PipelineInstance
  alias ExGoCD.Repo

  @doc "GET /api/feeds/pipelines.xml — Atom feed of all pipeline instances"
  def pipelines(conn, _params) do
    pipelines = Pipelines.list_pipelines()

    instances =
      PipelineInstance
      |> Ecto.Query.order_by(desc: :inserted_at)
      |> Ecto.Query.limit(20)
      |> Repo.all()

    feed_xml = render_feed(pipelines, instances, conn)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, feed_xml)
  end

  defp render_feed(pipelines, instances, conn) do
    now = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M:%SZ")
    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"

    entries =
      instances
      |> Enum.map(fn inst ->
        pipeline = Enum.find(pipelines, &(&1.id == inst.pipeline_id))
        pipeline_name = if pipeline, do: pipeline.name, else: "unknown"

        updated =
          (inst.inserted_at && Calendar.strftime(inst.inserted_at, "%Y-%m-%dT%H:%M:%SZ")) || now

        label = inst.label || "Unknown"

        """
        <entry>
          <title>#{esc("#{pipeline_name} ##{inst.counter} #{label}")}</title>
          <link href="#{esc("#{base_url}/pipelines/value_stream_map/#{pipeline_name}/#{inst.counter}")}" rel="alternate" type="text/html"/>
          <id>#{esc("urn:exgocd:pipeline:#{pipeline_name}:#{inst.counter}")}</id>
          <published>#{esc(updated)}</published>
          <updated>#{esc(updated)}</updated>
          <category term="#{esc(label)}"/>
          <content type="text">#{esc("#{pipeline_name} ##{inst.counter}: #{label}")}</content>
        </entry>
        """
      end)
      |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>ex_gocd Pipeline Feed</title>
      <id>#{esc("#{base_url}/api/feeds/pipelines.xml")}</id>
      <link href="#{esc("#{base_url}/api/feeds/pipelines.xml")}" rel="self" type="application/atom+xml"/>
      <link href="#{esc(base_url)}" rel="alternate" type="text/html"/>
      <updated>#{esc(now)}</updated>
      <author><name>ex_gocd</name></author>
    #{entries}
    </feed>
    """
  end

  defp esc(text),
    do:
      String.replace(text || "", ~w(& < > " '), fn
        "&" -> "&amp;"
        "<" -> "&lt;"
        ">" -> "&gt;"
        "\"" -> "&quot;"
        "'" -> "&apos;"
      end)

  @doc """
  GET /api/feeds/pipelines/:pipeline_name/stages.xml
  Atom feed of stage instances for a specific pipeline.
  """
  def pipeline_stages(conn, %{"pipeline_name" => pipeline_name}) do
    alias ExGoCD.Pipelines.StageInstance

    instances =
      StageInstance
      |> Ecto.Query.join(:inner, [si], pi in PipelineInstance,
        on: si.pipeline_instance_id == pi.id
      )
      |> Ecto.Query.join(:inner, [si, pi], p in ExGoCD.Pipelines.Pipeline,
        on: pi.pipeline_id == p.id
      )
      |> Ecto.Query.where([si, pi, p], p.name == ^pipeline_name)
      |> Ecto.Query.order_by(desc: :inserted_at)
      |> Ecto.Query.limit(50)
      |> Repo.all()
      |> Repo.preload([:pipeline_instance])

    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"
    now = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M:%SZ")

    entries =
      Enum.map(instances, fn si ->
        pi = si.pipeline_instance
        counter = if pi, do: pi.counter, else: "?"

        updated =
          (si.inserted_at && Calendar.strftime(si.inserted_at, "%Y-%m-%dT%H:%M:%SZ")) || now

        state_value = si.state || si.result || "Unknown"

        """
        <entry>
          <title>#{esc("#{pipeline_name} ##{counter} #{si.name} #{state_value}")}</title>
          <link href="#{esc("#{base_url}/go/pipelines/#{pipeline_name}/#{counter}/#{si.name}/#{si.counter}")}"/>
          <id>#{esc("urn:exgocd:stage:#{pipeline_name}:#{counter}:#{si.name}:#{si.counter}")}</id>
          <published>#{esc(updated)}</published>
          <updated>#{esc(updated)}</updated>
          <title>#{esc("#{pipeline_name} ##{counter} #{si.name}")}</title>
        </entry>
        """
      end)
      |> Enum.join("\n")

    xml = atom_feed("ex_gocd Stage Feed — #{pipeline_name}", base_url, now, entries)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, xml)
  end

  @doc """
  GET /api/feeds/pipelines/:pipeline/:counter/:stage/:stage_counter.xml
  Atom feed of a single stage instance with job details.
  """
  def stage(conn, %{
        "pipeline" => pipeline_name,
        "counter" => counter,
        "stage" => stage_name,
        "stage_counter" => stage_counter
      }) do
    alias ExGoCD.Pipelines.StageInstance

    counter_i = String.to_integer(counter)
    stage_counter_i = String.to_integer(stage_counter)

    instance =
      StageInstance
      |> Ecto.Query.join(:inner, [si], pi in PipelineInstance,
        on: si.pipeline_instance_id == pi.id
      )
      |> Ecto.Query.join(:inner, [si, pi], p in ExGoCD.Pipelines.Pipeline,
        on: pi.pipeline_id == p.id
      )
      |> Ecto.Query.where(
        [si, pi, p],
        p.name == ^pipeline_name and pi.counter == ^counter_i and si.name == ^stage_name and
          si.counter == ^stage_counter_i
      )
      |> Ecto.Query.limit(1)
      |> Repo.one()
      |> case do
        nil -> nil
        si -> Repo.preload(si, [:pipeline_instance, :job_instances])
      end

    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"
    now = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M:%SZ")

    entries =
      case instance do
        nil ->
          ""

        si ->
          _pi = si.pipeline_instance
          jobs = Map.get(si, :job_instances, []) || []

          stage_entry =
            "<entry>\n" <>
              "  <title>#{esc("#{pipeline_name} ##{counter} #{stage_name} (Stage ##{stage_counter})")}</title>\n" <>
              "  <id>#{esc("urn:exgocd:stage:#{pipeline_name}:#{counter}:#{stage_name}:#{stage_counter}")}</id>\n"

          job_entries =
            Enum.map(jobs, fn j ->
              state = j.state || j.result || "Unknown"

              "<entry>\n" <>
                "  <title>#{esc("#{pipeline_name} ##{counter} #{stage_name} #{j.name} #{state}")}</title>\n" <>
                "  <id>#{esc("urn:exgocd:job:#{pipeline_name}:#{counter}:#{stage_name}:#{stage_counter}:#{j.name}")}</id>\n" <>
                "</entry>\n"
            end)
            |> Enum.join()

          stage_entry <> job_entries
      end

    xml =
      atom_feed(
        "ex_gocd Stage — #{pipeline_name}/#{counter}/#{stage_name}/#{stage_counter}",
        base_url,
        now,
        entries
      )

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, xml)
  end

  @doc """
  GET /api/feeds/pipelines/:pipeline/:counter/:stage/:stage_counter/:job.xml
  Atom feed of a single job instance.
  """
  def job(conn, %{
        "pipeline" => pipeline_name,
        "counter" => counter,
        "stage" => stage_name,
        "stage_counter" => stage_counter,
        "job" => job_name
      }) do
    alias ExGoCD.Pipelines.{JobInstance, PipelineInstance, StageInstance}

    counter_i = String.to_integer(counter)
    stage_counter_i = String.to_integer(stage_counter)

    ji =
      JobInstance
      |> Ecto.Query.join(:inner, [ji], si in StageInstance, on: ji.stage_instance_id == si.id)
      |> Ecto.Query.join(:inner, [ji, si], pi in PipelineInstance,
        on: si.pipeline_instance_id == pi.id
      )
      |> Ecto.Query.join(:inner, [ji, si, pi], p in ExGoCD.Pipelines.Pipeline,
        on: pi.pipeline_id == p.id
      )
      |> Ecto.Query.where(
        [ji, si, pi, p],
        p.name == ^pipeline_name and pi.counter == ^counter_i and si.name == ^stage_name and
          si.counter == ^stage_counter_i and ji.name == ^job_name
      )
      |> Ecto.Query.limit(1)
      |> Repo.one()

    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"
    now = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M:%SZ")

    title = "#{pipeline_name} ##{counter} #{stage_name}/#{job_name}"

    entries =
      case ji do
        nil ->
          ""

        ji ->
          state = ji.state || ji.result || "Unknown"

          duration =
            if ji.started_at && ji.completed_at do
              diff = DateTime.diff(ji.completed_at, ji.started_at)
              "#{div(diff, 60)}m #{rem(diff, 60)}s"
            else
              "N/A"
            end

          """
          <entry>
            <title>#{esc("#{title} #{state} (#{duration})")}</title>
            <link href="#{esc("#{base_url}/go/tab/build/detail/#{pipeline_name}/#{counter}/#{stage_name}/#{stage_counter}/#{job_name}")}"/>
            <id>#{esc("urn:exgocd:job:#{pipeline_name}:#{counter}:#{stage_name}:#{stage_counter}:#{job_name}")}</id>
            <category term="#{esc(state)}"/>
            <content type="text">#{esc("#{title}: #{state} (#{duration})")}</content>
          </entry>
          """
      end

    xml = atom_feed("ex_gocd Job — #{title}", base_url, now, entries)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, xml)
  end

  @doc """
  GET /api/feeds/materials/:pipeline/:counter/:fingerprint.xml
  Atom feed of material modifications for a pipeline run.
  """
  def material(conn, %{
        "pipeline" => pipeline_name,
        "counter" => counter,
        "fingerprint" => fingerprint
      }) do
    alias ExGoCD.Pipelines.{Material, Modification}

    counter_i = String.to_integer(counter)

    mods =
      Modification
      |> Ecto.Query.join(:inner, [mod], mat in Material, on: mod.material_id == mat.id)
      |> Ecto.Query.join(:inner, [mod, mat], pi in PipelineInstance,
        on: mat.pipeline_instance_id == pi.id
      )
      |> Ecto.Query.join(:inner, [mod, mat, pi], p in ExGoCD.Pipelines.Pipeline,
        on: pi.pipeline_id == p.id
      )
      |> Ecto.Query.where(
        [mod, mat, pi, p],
        p.name == ^pipeline_name and pi.counter == ^counter_i and mat.fingerprint == ^fingerprint
      )
      |> Ecto.Query.order_by(desc: :inserted_at)
      |> Ecto.Query.limit(50)
      |> Repo.all()

    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"
    now = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M:%SZ")

    entries =
      Enum.map(mods, fn mod ->
        updated =
          (mod.inserted_at && Calendar.strftime(mod.inserted_at, "%Y-%m-%dT%H:%M:%SZ")) || now

        """
        <entry>
          <title>#{esc("#{mod.username}: #{mod.comment || "(no comment)"}")}</title>
          <id>#{esc("urn:exgocd:modification:#{mod.id}")}</id>
          <published>#{esc(updated)}</published>
          <updated>#{esc(updated)}</updated>
          <author><name>#{esc(mod.username || "unknown")}</name></author>
          <content type="text">#{esc("Revision #{mod.revision}: #{mod.comment || "no comment"}")}</content>
        </entry>
        """
      end)
      |> Enum.join("\n")

    xml =
      atom_feed(
        "ex_gocd Material Feed — #{pipeline_name}/#{counter}/#{fingerprint}",
        base_url,
        now,
        entries
      )

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, xml)
  end

  @doc """
  GET /api/feeds/jobs/scheduled.xml
  Atom feed of currently scheduled/waiting jobs.
  """
  def scheduled_jobs(conn, _params) do
    alias ExGoCD.Pipelines.JobInstance

    jobs =
      JobInstance
      |> Ecto.Query.where([ji], ji.state in ["Scheduled", "Assigned"])
      |> Ecto.Query.order_by(asc: :inserted_at)
      |> Ecto.Query.limit(50)
      |> Repo.all()
      |> Repo.preload([:stage_instance])

    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"
    now = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M:%SZ")

    entries =
      Enum.map(jobs, fn ji ->
        label = "Scheduled"

        """
        <entry>
          <title>#{esc("#{ji.name} — #{label}")}</title>
          <id>#{esc("urn:exgocd:job:scheduled:#{ji.id}")}</id>
          <category term="#{esc(label)}"/>
          <content type="text">#{esc("#{ji.name}: #{label}")}</content>
        </entry>
        """
      end)
      |> Enum.join("\n")

    xml = atom_feed("ex_gocd Scheduled Jobs", base_url, now, entries)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, xml)
  end

  defp atom_feed(title, base_url, now, entries) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>#{esc(title)}</title>
      <id>#{esc(base_url)}</id>
      <link href="#{esc(base_url)}" rel="self" type="application/atom+xml"/>
      <updated>#{esc(now)}</updated>
      <author><name>ex_gocd</name></author>
    #{entries}
    </feed>
    """
  end
end
