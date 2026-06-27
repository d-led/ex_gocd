defmodule ExGoCDWeb.FeedsController do
  @moduledoc """
  Atom/RSS feeds endpoint. Renders pipeline status as a feed
  compatible with CI monitoring tools (CCMenu, CCTray, etc.).
  """
  use ExGoCDWeb, :controller

  require Ecto.Query
  alias ExGoCD.Pipelines
  alias ExGoCD.Repo
  alias ExGoCD.Pipelines.PipelineInstance

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
        updated = inst.inserted_at || now
        status = inst.status || "Unknown"

        """
        <entry>
          <title>#{esc("#{pipeline_name} ##{inst.counter} #{status}")}</title>
          <link href="#{esc("#{base_url}/pipelines/value_stream_map/#{pipeline_name}/#{inst.counter}")}" rel="alternate" type="text/html"/>
          <id>#{esc("urn:exgocd:pipeline:#{pipeline_name}:#{inst.counter}")}</id>
          <published>#{esc(updated)}</published>
          <updated>#{esc(updated)}</updated>
          <category term="#{esc(status)}" label="status"/>
          <content type="text">#{esc("#{pipeline_name} ##{inst.counter}: #{status}")}</content>
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

  defp esc(text), do: String.replace(text || "", ~w(& < > " ')a, fn
    "&" -> "&amp;"
    "<" -> "&lt;"
    ">" -> "&gt;"
    "\"" -> "&quot;"
    "'" -> "&apos;"
  end)
end
