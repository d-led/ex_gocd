defmodule ExGoCD.ConfigXml do
  @moduledoc """
  Serializes pipeline configuration as GoCD-compatible cruise-config.xml.
  Uses simple string concatenation.
  """

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  @doc "Returns the full cruise-config XML string."
  def generate do
    pipelines = Pipelines.list_pipelines() |> Repo.preload([:materials, stages: [jobs: :tasks]])
    pipeline_xml = pipelines |> Enum.map(&render_pipeline/1) |> Enum.join("\n")
    """
    <?xml version="1.0" encoding="utf-8"?>
    <cruise xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="cruise-config.xsd" schemaVersion="120">
      <server serverId="ex-gocd" artifactsdir="artifacts" />
      <pipelines group="default">
    #{pipeline_xml}
      </pipelines>
    </cruise>
    """
  end

  defp esc(text) when is_binary(text) do
    text |> String.replace("&", "&amp;") |> String.replace("<", "&lt;") |> String.replace(">", "&gt;") |> String.replace("\"", "&quot;")
  end
  defp esc(other), do: to_string(other)

  defp attrs(kvs) do
    Enum.map_join(kvs, " ", fn {k, v} -> "#{k}=\"#{if is_boolean(v), do: to_string(v), else: esc(v)}\"" end)
  end

  defp tag2(name, attrs_map) do
    "<#{name} #{attrs(attrs_map)} />"
  end

  defp tag3(name, attrs_map, content) do
    "<#{name} #{attrs(attrs_map)}>#{content}</#{name}>"
  end

  defp render_pipeline(pipeline) do
    tag3("pipeline", %{name: pipeline.name, isLocked: pipeline.locked},
      tag3("params", %{}, render_params(pipeline)) <>
      tag3("timer", %{onlyOnChanges: pipeline.timer_only_on_changes || false}, esc(pipeline.timer || "")) <>
      tag3("materials", %{}, Enum.map_join(pipeline.materials || [], "", &render_material/1)) <>
      tag3("environmentvariables", %{}, render_all_env_vars(pipeline)) <>
      tag3("stages", %{}, Enum.map_join(pipeline.stages || [], "", &render_stage/1))
    )
  end

  defp render_params(pipeline) do
    (pipeline.parameters || %{}) |> Enum.map_join("", fn {k, v} -> tag3("param", %{name: k}, esc(v)) end)
  end

  defp render_all_env_vars(pipeline) do
    render_env_vars(pipeline.environment_variables) <> render_secure_vars(pipeline.secure_variables)
  end

  defp render_material(%{type: "git"} = mat) do
    tag2("git", %{url: mat.url, branch: mat.branch || "master", dest: mat.name || mat.url, materialName: mat.name || mat.url, autoUpdate: mat.auto_update != false})
  end
  defp render_material(%{type: "dependency"} = mat) do
    tag2("pipeline", %{pipelineName: mat.pipeline_name || mat.name, stageName: mat.stage_name || "build", materialName: mat.name})
  end
  defp render_material(mat), do: tag2(mat.type || "git", %{url: mat.url || ""})

  defp render_env_vars(vars) when is_map(vars) and map_size(vars) > 0 do
    vars |> Enum.reject(fn {_k, v} -> is_map(v) and v["secure"] end) |> Enum.map_join("", fn {k, v} ->
      val = if is_map(v), do: v["value"] || v[:value] || "", else: v
      tag3("variable", %{name: k}, tag3("value", %{}, esc(val)))
    end)
  end
  defp render_env_vars(_), do: ""

  defp render_secure_vars(vars) when is_map(vars) and map_size(vars) > 0 do
    vars |> Enum.filter(fn {_k, v} -> is_map(v) and v["secure"] end) |> Enum.map_join("", fn {k, v} ->
      val = v["value"] || v[:value] || ""
      tag3("secureVariable", %{name: k}, tag3("encryptedValue", %{}, esc(val)))
    end)
  end
  defp render_secure_vars(_), do: ""

  defp render_stage(stage) do
    tag3("stage", %{name: stage.name, fetchMaterials: stage.fetch_materials != false, cleanWorkingDir: stage.clean_working_directory || false},
      tag2("approval", %{type: stage.approval_type || "success"}) <>
      tag3("environmentvariables", %{}, render_env_vars(stage.environment_variables || %{}) <> render_secure_vars(stage.secure_variables || %{})) <>
      tag3("jobs", %{}, Enum.map_join(stage.jobs || [], "", &render_job/1))
    )
  end

  defp render_job(job) do
    resources = Enum.map_join(job.resources || [], "", fn r -> tag3("resource", %{}, esc(r)) end)
    tasks = Enum.map_join(job.tasks || [], "", &render_task/1)
    tag3("job", %{name: job.name, runInstanceCount: job.run_instance_count || 1, timeout: job.timeout || 0, runOnAllAgents: job.run_on_all_agents || false},
      tag3("resources", %{}, resources) <> tag3("tasks", %{}, tasks)
    )
  end

  defp render_task(%{type: "exec"} = task) do
    args = Enum.map_join(task.args || task.arguments || [], "", fn a -> tag3("arg", %{}, esc(a)) end)
    tag3("exec", %{command: task.command || ""}, args)
  end
  defp render_task(%{type: "fetch"} = task) do
    tag2("fetchartifact", %{pipeline: task.pipeline || "", stage: task.stage || "", job: task.job || "", srcfile: task.src_file || task.source || "", dest: task.dest || "", artifactOrigin: "gocd"})
  end
  defp render_task(_task), do: tag3("exec", %{command: "echo"}, tag3("arg", %{}, "unknown task"))
end
