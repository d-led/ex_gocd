defmodule ExGoCDWeb.CCTrayController do
  @moduledoc """
  CCTray XML feed for CI monitoring tools.

  Reports each stage of each pipeline's latest instance as a `<Project>` element
  following the CCTray standard (https://cctray.org/).

  Route: GET /go/cctray.xml
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines

  @doc """
  Returns the CCTray XML feed with all pipelines and their latest stage statuses.
  """
  def index(conn, _params) do
    pipelines = Pipelines.list_for_dashboard()
    xml = build_cctray_xml(pipelines, conn)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  defp build_cctray_xml(pipelines, conn) do
    projects_xml =
      pipelines
      |> Enum.flat_map(&pipeline_to_projects/1)
      |> Enum.map(&project_to_xml(&1, conn))
      |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="utf-8"?>
    <Projects>
    #{projects_xml}
    </Projects>
    """
  end

  defp pipeline_to_projects(pipeline) do
    stage_list = pipeline[:stages] || []
    counter = pipeline[:counter] || 0

    Enum.map(stage_list, fn stage ->
      %{
        name: "#{pipeline[:name]} :: #{stage[:name]}",
        activity: activity(stage),
        last_build_status: cctray_status(stage[:status]),
        last_build_label: "#{counter}",
        last_build_time: format_time(pipeline[:last_run]),
        web_url:
          stage_web_url(
            conn_module: nil,
            pipeline_name: pipeline[:name],
            pipeline_counter: counter,
            stage_name: stage[:name],
            stage_counter: counter
          )
      }
    end)
  end

  defp activity(%{status: "Building"}), do: "Building"
  defp activity(_), do: "Sleeping"

  defp cctray_status("Passed"), do: "Success"
  defp cctray_status("Failed"), do: "Failure"
  defp cctray_status("Cancelled"), do: "Exception"
  defp cctray_status("Building"), do: "Success"
  defp cctray_status("Awaiting"), do: "Success"
  defp cctray_status(_), do: "Unknown"

  defp format_time(nil), do: ""
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")

  defp project_to_xml(project, _conn) do
    ~s(  <Project name="#{escape_xml(project.name)}" activity="#{project.activity}" lastBuildStatus="#{project.last_build_status}" lastBuildLabel="#{project.last_build_label}" lastBuildTime="#{project.last_build_time}" webUrl="#{escape_xml(project.web_url)}" />)
  end

  defp stage_web_url(opts) do
    name = opts[:pipeline_name]
    counter = opts[:pipeline_counter]
    stage = opts[:stage_name]
    stage_counter = opts[:stage_counter]

    # Build relative path; host/port come from Endpoint config
    "/go/pipelines/#{name}/#{counter}/#{stage}/#{stage_counter}"
  end

  defp escape_xml(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
