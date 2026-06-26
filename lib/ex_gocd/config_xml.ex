defmodule ExGoCD.ConfigXml do
  @moduledoc """
  Serializes and deserializes pipeline configuration as GoCD-compatible
  cruise-config.xml. Uses simple string concatenation for export and
  Erlang :xmerl for import.
  """

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  # ── Export ────────────────────────────────────────────────────────

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

  # ── Import ────────────────────────────────────────────────────────

  @doc """
  Parses a cruise-config.xml string and returns a list of pipeline maps
  suitable for insertion via `Pipelines.create_pipeline/1`.
  Returns `{:ok, pipelines}` or `{:error, reason}`.
  """
  def from_xml(xml_string) when is_binary(xml_string) do
    result =
      try do
        {:ok, :xmerl_scan.string(String.to_charlist(xml_string), quiet: true)}
      catch
        :exit, {:fatal, reason} -> {:fatal, reason}
        kind, reason -> {:error, {kind, reason}}
      end

    case result do
      {:ok, {doc, []}} ->
        {:ok, extract_pipelines(doc)}

      {:ok, {doc, _rest}} ->
        # Some content remained unparsed — still try to extract pipelines
        {:ok, extract_pipelines(doc)}

      {:fatal, reason} ->
        {:error, "XML parse error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Unexpected error: #{inspect(reason)}"}
    end
  end

  @doc """
  Imports pipelines from XML, creating new ones and updating existing ones by name.
  Returns `{:ok, count}` with the number of pipelines created/updated.
  """
  def import_from_xml(xml_string) when is_binary(xml_string) do
    case from_xml(xml_string) do
      {:ok, pipelines} ->
        count =
          Enum.reduce(pipelines, 0, fn pipeline, acc ->
            case Pipelines.get_pipeline_by_name(pipeline.name) do
              nil -> Pipelines.create_pipeline(pipeline); acc + 1
              _existing -> Pipelines.update_pipeline(pipeline); acc + 1
            end
          end)

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── XML extraction helpers ─────────────────────────────────────────

  defp extract_pipelines(doc) do
    doc
    |> find_element(:pipelines)
    |> case do
      nil -> []
      pipelines_el -> find_elements(pipelines_el, :pipeline) |> Enum.map(&parse_pipeline/1)
    end
  end

  defp parse_pipeline(el) do
    timer_el = find_child(el, :timer)
    %{
      name: attr(el, :name) |> to_string(),
      locked: attr(el, :isLocked) == "true",
      group: "default",
      timer: timer_text(timer_el),
      timer_only_on_changes: attr(timer_el, :onlyOnChanges) == "true",
      parameters: parse_params(el),
      materials: parse_materials(el),
      environment_variables: parse_env_vars(el),
      secure_variables: parse_secure_vars(el),
      stages: parse_stages(el)
    }
  end

  defp parse_params(el) do
    find_child(el, :params)
    |> case do
      nil -> %{}
      params_el ->
        find_elements(params_el, :param)
        |> Enum.reduce(%{}, fn p, acc ->
          Map.put(acc, to_string(attr(p, :name)), text_content(p) |> to_string())
        end)
    end
  end

  defp parse_materials(el) do
    find_child(el, :materials)
    |> case do
      nil -> []
      mats_el ->
        find_elements(mats_el)
        |> Enum.map(&parse_material/1)
    end
  end

  defp parse_material(el) do
    tag = elem(el, 1)
    case tag do
      :git ->
        %{type: "git", url: to_string(attr(el, :url)), branch: to_string(attr(el, :branch) || "master"),
          name: to_string(attr(el, :materialName) || attr(el, :dest) || attr(el, :url)),
          auto_update: attr(el, :autoUpdate) != "false"}

      :pipeline ->
        %{type: "dependency", pipeline_name: to_string(attr(el, :pipelineName)),
          stage_name: to_string(attr(el, :stageName) || "build"),
          name: to_string(attr(el, :materialName) || attr(el, :pipelineName))}

      other ->
        %{type: to_string(other), url: to_string(attr(el, :url) || "")}
    end
  end

  defp parse_env_vars(el) do
    find_child(el, :environmentvariables)
    |> case do
      nil -> %{}
      env_el ->
        find_elements(env_el, :variable)
        |> Enum.reduce(%{}, fn v, acc ->
          name = to_string(attr(v, :name))
          value_el = find_child(v, :value)
          value = if value_el, do: text_content(value_el) |> to_string(), else: ""
          Map.put(acc, name, %{"value" => value, "secure" => false})
        end)
    end
  end

  defp parse_secure_vars(el) do
    find_child(el, :environmentvariables)
    |> case do
      nil -> %{}
      env_el ->
        find_elements(env_el, :secureVariable)
        |> Enum.reduce(%{}, fn v, acc ->
          name = to_string(attr(v, :name))
          enc_el = find_child(v, :encryptedValue)
          value = if enc_el, do: text_content(enc_el) |> to_string(), else: ""
          Map.put(acc, name, %{"value" => value, "secure" => true})
        end)
    end
  end

  defp parse_stages(el) do
    find_child(el, :stages)
    |> case do
      nil -> []
      stages_el ->
        find_elements(stages_el, :stage)
        |> Enum.map(&parse_stage/1)
    end
  end

  defp parse_stage(el) do
    %{
      name: to_string(attr(el, :name)),
      fetch_materials: attr(el, :fetchMaterials) != "false",
      clean_working_directory: attr(el, :cleanWorkingDir) == "true",
      approval_type: (find_child(el, :approval) |> case do nil -> "success"; a -> to_string(attr(a, :type) || "success") end),
      environment_variables: parse_env_vars(el),
      secure_variables: parse_secure_vars(el),
      jobs: parse_jobs(el)
    }
  end

  defp parse_jobs(el) do
    find_child(el, :jobs)
    |> case do
      nil -> []
      jobs_el ->
        find_elements(jobs_el, :job)
        |> Enum.map(&parse_job/1)
    end
  end

  defp parse_job(el) do
    %{
      name: to_string(attr(el, :name)),
      run_instance_count: parse_int(attr(el, :runInstanceCount), 1),
      timeout: parse_int(attr(el, :timeout), 0),
      run_on_all_agents: attr(el, :runOnAllAgents) == "true",
      resources: parse_resources(el),
      tasks: parse_tasks(el)
    }
  end

  defp parse_resources(el) do
    find_child(el, :resources)
    |> case do
      nil -> []
      res_el ->
        find_elements(res_el, :resource) |> Enum.map(fn r -> text_content(r) |> to_string() end)
    end
  end

  defp parse_tasks(el) do
    find_child(el, :tasks)
    |> case do
      nil -> []
      tasks_el ->
        find_elements(tasks_el)
        |> Enum.map(&parse_task/1)
    end
  end

  defp parse_task(el) do
    tag = elem(el, 1)
    case tag do
      :exec ->
        command = to_string(attr(el, :command) || "")
        args = find_elements(el, :arg) |> Enum.map(fn a -> text_content(a) |> to_string() end)
        runif_el = find_child(el, :runif)
        runif = if runif_el, do: to_string(attr(runif_el, :status) || "passed"), else: "passed"
        %{type: "exec", command: command, args: args, run_if: [runif]}

      :fetchartifact ->
        %{type: "fetch", pipeline: to_string(attr(el, :pipeline) || ""), stage: to_string(attr(el, :stage) || ""),
          job: to_string(attr(el, :job) || ""), src_file: to_string(attr(el, :srcfile) || ""),
          dest: to_string(attr(el, :dest) || ""), artifact_origin: to_string(attr(el, :artifactOrigin) || "gocd")}

      _ ->
        %{type: "exec", command: "echo", args: ["unknown task: #{tag}"]}
    end
  end

  # ── xmerl navigation helpers ──────────────────────────────────────

  defp find_element(doc, name) when is_tuple(doc) and elem(doc, 0) == :xmlElement do
    if elem(doc, 1) == name, do: doc, else: find_child(doc, name)
  end

  defp find_child(nil, _name), do: nil
  defp find_child(el, name) do
    el |> elem(8) |> Enum.find(&(elem(&1, 0) == :xmlElement and elem(&1, 1) == name))
  end

  defp find_elements(el, name \\ nil) do
    el
    |> elem(8)
    |> Enum.filter(fn child ->
      elem(child, 0) == :xmlElement and (is_nil(name) or elem(child, 1) == name)
    end)
  end

  defp attr(nil, _name), do: nil
  defp attr(el, name) do
    el
    |> elem(7)
    |> Enum.find_value(nil, fn a -> if elem(a, 1) == name, do: elem(a, 8) |> to_string(), else: nil end)
  end

  defp text_content(el) do
    el
    |> elem(8)
    |> Enum.find_value("", fn
      child when elem(child, 0) == :xmlText -> elem(child, 4) |> to_string()
      _ -> nil
    end)
  end

  defp find_text(el, _name) when is_nil(el), do: nil
  defp find_text(el, name) do
    find_child(el, name) |> case do
      nil -> nil
      child -> text_content(child)
    end
  end

  defp timer_text(nil), do: nil
  defp timer_text(el), do: text_content(el)

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) when is_list(str), do: parse_int(to_string(str), default)
  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end
end
