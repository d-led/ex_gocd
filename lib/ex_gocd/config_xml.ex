defmodule ExGoCD.ConfigXml do
  @moduledoc """
  Serializes and deserializes pipeline configuration as GoCD-compatible
  cruise-config.xml. Uses simple string concatenation for export and
  Erlang :xmerl for import.
  """

  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  import Ecto.Query, only: [where: 3]

  # ── Export ────────────────────────────────────────────────────────

  @doc "Returns the full cruise-config XML string."
  def generate do
    pipelines = Pipelines.list_pipelines() |> Repo.preload([:materials, stages: [jobs: :tasks]])
    pipeline_xml = pipelines |> Enum.map(&render_pipeline/1) |> Enum.join("\n")

    templates_xml = render_templates()
    environments_xml = render_environments()
    security_xml = render_security()
    elastic_xml = render_elastic_profiles()
    cluster_xml = render_cluster_profiles()

    """
    <?xml version="1.0" encoding="utf-8"?>
    <cruise xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="cruise-config.xsd" schemaVersion="120">
      <server serverId="ex-gocd" artifactsdir="artifacts" />
    #{security_xml}
    #{environments_xml}
      <pipelines group="default">
    #{pipeline_xml}
      </pipelines>
    #{templates_xml}
    #{elastic_xml}
    #{cluster_xml}
    </cruise>
    """
  end

  defp esc(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp esc(other), do: to_string(other)

  defp attrs(kvs) do
    Enum.map_join(kvs, " ", fn {k, v} ->
      "#{k}=\"#{if is_boolean(v), do: to_string(v), else: esc(v)}\""
    end)
  end

  defp tag2(name, attrs_map) do
    "<#{name} #{attrs(attrs_map)} />"
  end

  defp tag3(name, attrs_map, content) do
    "<#{name} #{attrs(attrs_map)}>#{content}</#{name}>"
  end

  defp render_pipeline(pipeline) do
    tag3(
      "pipeline",
      %{name: pipeline.name, isLocked: pipeline.locked},
      tag3("params", %{}, render_params(pipeline)) <>
        tag3(
          "timer",
          %{onlyOnChanges: pipeline.timer_only_on_changes || false},
          esc(pipeline.timer || "")
        ) <>
        tag3("materials", %{}, Enum.map_join(pipeline.materials || [], "", &render_material/1)) <>
        tag3("environmentvariables", %{}, render_all_env_vars(pipeline)) <>
        tag3("stages", %{}, Enum.map_join(pipeline.stages || [], "", &render_stage/1))
    )
  end

  defp render_params(pipeline) do
    (pipeline.parameters || %{})
    |> Enum.map_join("", fn {k, v} -> tag3("param", %{name: k}, esc(v)) end)
  end

  defp render_all_env_vars(pipeline) do
    render_env_vars(pipeline.environment_variables) <>
      render_secure_vars(pipeline.secure_variables)
  end

  defp render_material(%{type: "git"} = mat) do
    destination = material_destination(mat)

    tag2("git", %{
      url: mat.url,
      branch: mat.branch || "master",
      dest: destination,
      materialName: material_attribute(mat, "material_name") || destination,
      autoUpdate: mat.auto_update != false
    })
  end

  defp render_material(%{type: "dependency"} = mat) do
    pipeline_name = material_attribute(mat, "pipeline_name") || mat.url

    tag2("pipeline", %{
      pipelineName: pipeline_name,
      stageName: material_attribute(mat, "stage_name") || "build",
      materialName: material_attribute(mat, "material_name") || pipeline_name
    })
  end

  defp render_material(%{type: "svn"} = mat) do
    tsc = mat.type_specific_config || %{}
    check_externals = tsc["check_externals"]
    destination = material_destination(mat)

    base_attrs = %{
      url: mat.url,
      dest: destination,
      materialName: material_attribute(mat, "material_name") || destination,
      autoUpdate: mat.auto_update != false
    }

    attrs =
      base_attrs
      |> maybe_put_attr(:username, mat.username)
      |> maybe_put_attr(:password, tsc["password"])
      |> maybe_put_attr(:checkexternals, check_externals)

    tag2("svn", attrs)
  end

  defp render_material(%{type: type} = mat) when type in ["hg", "p4", "tfs"] do
    destination = material_destination(mat)

    tag2(type, %{
      url: mat.url || "",
      dest: destination,
      materialName: material_attribute(mat, "material_name") || destination
    })
  end

  defp render_material(mat), do: tag2(mat.type || "git", %{url: mat.url || ""})

  # GoCD checks a material out into `dest`, which defaults to the material name.
  defp material_destination(mat) do
    mat.destination || material_attribute(mat, "material_name") || mat.url
  end

  # Per-type material attributes, stored in `type_specific_config` because the
  # schema has no column for them. Both string and atom keys are accepted:
  # anything that went through a JSON round-trip has strings.
  defp material_attribute(mat, key) do
    tsc = mat.type_specific_config || %{}

    case Map.get(tsc, key) || Map.get(tsc, String.to_existing_atom(key)) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp render_env_vars(vars) when is_map(vars) and map_size(vars) > 0 do
    vars
    |> Enum.reject(fn {_k, v} -> is_map(v) and v["secure"] end)
    |> Enum.map_join("", fn {k, v} ->
      val = if is_map(v), do: v["value"] || v[:value] || "", else: v
      tag3("variable", %{name: k}, tag3("value", %{}, esc(val)))
    end)
  end

  defp render_env_vars(_), do: ""

  defp render_secure_vars(vars) when is_map(vars) and map_size(vars) > 0 do
    vars
    |> Enum.filter(fn {_k, v} -> is_map(v) and v["secure"] end)
    |> Enum.map_join("", fn {k, v} ->
      val = v["value"] || v[:value] || ""
      tag3("secureVariable", %{name: k}, tag3("encryptedValue", %{}, esc(val)))
    end)
  end

  defp render_secure_vars(_), do: ""

  defp render_stage(stage) do
    tag3(
      "stage",
      %{
        name: stage.name,
        fetchMaterials: stage.fetch_materials != false,
        cleanWorkingDir: stage.clean_working_directory || false
      },
      tag2("approval", %{type: stage.approval_type || "success"}) <>
        tag3(
          "environmentvariables",
          %{},
          render_env_vars(stage.environment_variables || %{}) <>
            render_secure_vars(stage.secure_variables || %{})
        ) <>
        tag3("jobs", %{}, Enum.map_join(stage.jobs || [], "", &render_job/1))
    )
  end

  defp render_job(job) do
    resources = Enum.map_join(job.resources || [], "", fn r -> tag3("resource", %{}, esc(r)) end)
    tabs_xml = render_tabs(job.tabs || %{})
    tasks = Enum.map_join(job.tasks || [], "", &render_task/1)
    artifacts_xml = render_artifacts(job.artifact_configs || %{})

    tag3(
      "job",
      %{
        name: job.name,
        runInstanceCount: job.run_instance_count || 1,
        timeout: job.timeout || 0,
        runOnAllAgents: job.run_on_all_agents || false
      },
      tag3("resources", %{}, resources) <>
        tabs_xml <>
        tag3("tasks", %{}, tasks) <>
        artifacts_xml
    )
  end

  defp render_task(%{type: "exec"} = task) do
    args =
      Enum.map_join(task_attribute(task, :arguments, :args) || [], "", &tag3("arg", %{}, esc(&1)))

    tag3("exec", %{command: task.command || ""}, args)
  end

  # A fetch task keeps its source coordinates in `arguments`, the same shape the
  # scheduler reads: [pipeline, stage, job, src_file, dest].
  defp render_task(%{type: "fetch"} = task) do
    {pipeline, stage, job, src_file, dest} =
      case task_attribute(task, :arguments, :args) || [] do
        [pipeline, stage, job, src_file, dest] -> {pipeline, stage, job, src_file, dest}
        [stage, job, src_file, dest] -> {"", stage, job, src_file, dest}
        _ -> {"", "", "", "", ""}
      end

    tag2("fetchartifact", %{
      pipeline: pipeline,
      stage: stage,
      job: job,
      srcfile: src_file,
      dest: dest,
      artifactOrigin: "gocd"
    })
  end

  defp render_task(_task), do: tag3("exec", %{command: "echo"}, tag3("arg", %{}, "unknown task"))

  # Reads an attribute that exists under two names: the stored struct uses one,
  # the XML-shaped map the parser produces uses the other.
  defp task_attribute(task, primary, fallback) do
    Map.get(task, primary) || Map.get(task, fallback)
  end

  defp render_tabs(tabs) when is_map(tabs) and tabs != %{} do
    inner =
      Enum.map_join(tabs, "", fn {name, path} ->
        ~s'<tab name="#{esc(name)}" path="#{esc(path)}" />'
      end)

    tag3("tabs", %{}, inner)
  end

  defp render_tabs(_), do: ""

  defp render_artifacts(artifact_configs) when is_map(artifact_configs) do
    items = artifact_configs["artifacts"] || []

    if is_list(items) and items != [] do
      inner =
        Enum.map_join(items, "", fn art ->
          type = art["type"] || "build"
          src = art["src"] || ""
          dest = art["dest"] || ""
          ~s'<artifact type="#{esc(type)}" src="#{esc(src)}" dest="#{esc(dest)}" />'
        end)

      tag3("artifacts", %{}, inner)
    else
      ""
    end
  end

  defp render_artifacts(_), do: ""

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
        {:ok, extract_pipelines(doc), extract_elastic_profiles(doc)}

      {:ok, {doc, _rest}} ->
        {:ok, extract_pipelines(doc), extract_elastic_profiles(doc)}

      {:fatal, reason} ->
        {:error, "XML parse error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Unexpected error: #{inspect(reason)}"}
    end
  end

  @doc """
  Imports pipelines and elastic agent profiles from XML, creating new ones
  and updating existing ones by name. Returns `{:ok, counts}` where counts is
  a map with `:pipelines` and `:elastic_profiles` keys.
  """
  def import_from_xml(xml_string) when is_binary(xml_string) do
    with {:ok, pipelines, elastic_profiles} <- from_xml(xml_string),
         :ok <- import_pipelines(pipelines),
         :ok <- import_elastic_profiles(elastic_profiles) do
      {:ok, %{pipelines: length(pipelines), elastic_profiles: length(elastic_profiles)}}
    end
  end

  # ── Import: what is parsed has to be stored ───────────────────────
  #
  # Pipelines are stored in two passes. A dependency material names a pipeline
  # that may be declared later in the same document, so every pipeline has to
  # exist before any dependency material can be attached.

  defp import_pipelines(definitions) do
    case Enum.reduce_while(definitions, [], &store_pipeline_or_halt/2) do
      {:error, _} = error -> error
      stored -> attach_dependency_materials(Enum.reverse(stored))
    end
  end

  defp store_pipeline_or_halt(definition, stored) do
    case store_pipeline(definition) do
      {:ok, pipeline} -> {:cont, [{pipeline, definition} | stored]}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp store_pipeline(definition) do
    with {:ok, pipeline} <- upsert_pipeline(definition),
         :ok <- store_materials(pipeline, self_sourced_materials(definition.materials)),
         :ok <- store_stages(pipeline, definition.stages) do
      {:ok, pipeline}
    end
  end

  defp attach_dependency_materials(stored) do
    Enum.reduce_while(stored, :ok, fn {pipeline, definition}, :ok ->
      case store_materials(pipeline, dependency_materials(definition.materials)) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp self_sourced_materials(materials), do: Enum.reject(materials, &dependency?/1)

  defp dependency_materials(materials), do: Enum.filter(materials, &dependency?/1)

  defp dependency?(material), do: Map.get(material, :type) == "dependency"

  defp upsert_pipeline(definition) do
    attrs = %{
      name: definition.name,
      group: definition.group,
      locked: definition.locked,
      timer: definition.timer,
      timer_only_on_changes: definition.timer_only_on_changes,
      parameters: definition.parameters,
      environment_variables: definition.environment_variables,
      secure_variables: Map.get(definition, :secure_variables) || %{}
    }

    result =
      case Pipelines.get_pipeline_by_name(definition.name) do
        nil -> Pipelines.create_pipeline(attrs)
        existing -> Pipelines.update_pipeline(existing, attrs)
      end

    as_stored(result, definition.name)
  end

  defp store_materials(_pipeline, []), do: :ok

  defp store_materials(pipeline, materials) do
    Enum.reduce_while(materials, :ok, fn material, :ok ->
      case Pipelines.create_material_for_pipeline(pipeline, material_attributes(material)) do
        {:ok, _material} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error, "\"#{pipeline.name}\" material could not be imported: #{inspect(reason)}"}}
      end
    end)
  end

  defp material_attributes(%{type: "dependency"} = material) do
    # A dependency material is identified by the pipeline it watches, which this
    # codebase keeps in `url`.
    material
    |> Map.take([:type, :pipeline_name, :stage_name, :name])
    |> Map.put(:url, Map.get(material, :pipeline_name))
  end

  defp material_attributes(material) do
    Map.take(material, [
      :type,
      :url,
      :branch,
      :username,
      :destination,
      :auto_update,
      :name,
      :type_specific_config
    ])
  end

  defp store_stages(_pipeline, []), do: :ok

  defp store_stages(pipeline, stages) do
    existing = Repo.preload(pipeline, stages: [jobs: :tasks]).stages

    Enum.reduce_while(stages, :ok, fn definition, :ok ->
      with {:ok, stage} <- upsert_stage(pipeline, definition, existing),
           :ok <- store_jobs(stage, definition.jobs) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp upsert_stage(pipeline, definition, existing_stages) do
    attrs = %{
      name: definition.name,
      pipeline_id: pipeline.id,
      fetch_materials: definition.fetch_materials,
      clean_working_directory: definition.clean_working_directory,
      approval_type: definition.approval_type,
      environment_variables: definition.environment_variables
    }

    result =
      case Enum.find(existing_stages, &(&1.name == definition.name)) do
        nil -> Pipelines.create_stage(attrs)
        stage -> Pipelines.update_stage(stage, attrs)
      end

    as_stored(result, "#{pipeline.name}/#{definition.name}")
  end

  defp store_jobs(_stage, []), do: :ok

  defp store_jobs(stage, jobs) do
    existing = Repo.preload(stage, jobs: :tasks).jobs

    Enum.reduce_while(jobs, :ok, fn definition, :ok ->
      with {:ok, job} <- upsert_job(stage, definition, existing),
           :ok <- store_tasks(job, definition.tasks) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp upsert_job(stage, definition, existing_jobs) do
    # `run_instance_count` and `timeout` are stored as text (see Pipelines.job_config),
    # even though the XML carries them as numbers.
    attrs = %{
      name: definition.name,
      stage_id: stage.id,
      run_instance_count: stored_number(definition.run_instance_count),
      timeout: stored_number(definition.timeout),
      run_on_all_agents: definition.run_on_all_agents,
      resources: definition.resources,
      tabs: definition.tabs,
      artifact_configs: definition.artifact_configs
    }

    result =
      case Enum.find(existing_jobs, &(&1.name == definition.name)) do
        nil -> Pipelines.create_job(attrs)
        job -> Pipelines.update_job(job, attrs)
      end

    as_stored(result, "#{stage.name}/#{definition.name}")
  end

  defp stored_number(nil), do: nil
  defp stored_number(number), do: to_string(number)

  # Tasks carry no name to match on, so the job's tasks are replaced wholesale.
  defp store_tasks(job, tasks) do
    ExGoCD.Pipelines.Task
    |> where([task], task.job_id == ^job.id)
    |> Repo.delete_all()

    Enum.reduce_while(tasks, :ok, fn definition, :ok ->
      result = Pipelines.create_task(Map.put(task_attributes(definition), :job_id, job.id))

      case as_stored(result, "#{job.name} task") do
        {:ok, _task} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp task_attributes(%{type: "fetch"} = task) do
    %{
      type: "fetch",
      arguments: [task.pipeline, task.stage, task.job, task.src_file, task.dest]
    }
  end

  defp task_attributes(task) do
    %{
      type: Map.get(task, :type) || "exec",
      command: Map.get(task, :command),
      arguments: Map.get(task, :args) || Map.get(task, :arguments) || [],
      run_if: task_run_if(task)
    }
  end

  defp task_run_if(task) do
    case Map.get(task, :run_if) do
      [status | _] -> status
      status when is_binary(status) -> status
      _ -> "passed"
    end
  end

  defp import_elastic_profiles(profiles) do
    Enum.reduce_while(profiles, :ok, fn profile, :ok ->
      result =
        case Repo.get_by(ExGoCD.ElasticAgentProfiles.ElasticAgentProfile, name: profile.name) do
          nil -> ExGoCD.ElasticAgentProfiles.create_profile(profile)
          existing -> ExGoCD.ElasticAgentProfiles.update_profile(existing, profile)
        end

      case as_stored(result, profile.name) do
        {:ok, _profile} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp as_stored({:ok, record}, _label), do: {:ok, record}

  defp as_stored({:error, %Ecto.Changeset{} = changeset}, label) do
    {:error, "#{inspect(label)} could not be imported: #{changeset_message(changeset)}"}
  end

  defp as_stored({:error, reason}, label) do
    {:error, "#{inspect(label)} could not be imported: #{inspect(reason)}"}
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

  # ── XML extraction helpers ─────────────────────────────────────────

  defp extract_pipelines(doc) do
    doc
    |> find_element(:pipelines)
    |> case do
      nil ->
        []

      pipelines_el ->
        group = to_string(attr(pipelines_el, :group) || "default")

        find_elements(pipelines_el, :pipeline)
        |> Enum.map(&parse_pipeline(&1, group))
    end
  end

  defp extract_elastic_profiles(doc) do
    doc
    |> find_element(:agentProfiles)
    |> case do
      nil -> []
      ap_el -> find_elements(ap_el, :agentProfile) |> Enum.map(&parse_agent_profile/1)
    end
  end

  defp parse_agent_profile(el) do
    props =
      el
      |> find_elements(:property)
      |> Enum.reduce(%{}, &reduce_agent_property/2)

    %{
      name: attr(el, :name) |> to_string(),
      plugin_id: attr(el, :pluginId) |> to_string(),
      cluster_profile_id: attr(el, :clusterProfileId) |> to_string(),
      properties: props
    }
  end

  defp reduce_agent_property(prop_el, acc) do
    key_el = find_child(prop_el, :key)
    value_el = find_child(prop_el, :value)

    if key_el && value_el do
      key = text_content(key_el) |> to_string()
      value = text_content(value_el) |> to_string()
      Map.put(acc, key, parse_property_value(key, value))
    else
      acc
    end
  end

  defp parse_property_value(key, value) when key in ["MaxCPU", "MinCPU", "MinAgents"] do
    case Integer.parse(value) do
      {n, _} -> n
      _ -> value
    end
  end

  defp parse_property_value(_key, value) do
    if String.starts_with?(value, "{") || String.starts_with?(value, "[") do
      case Jason.decode(value) do
        {:ok, decoded} -> decoded
        _ -> value
      end
    else
      value
    end
  end

  defp parse_pipeline(el, group) do
    timer_el = find_child(el, :timer)

    %{
      name: attr(el, :name) |> to_string(),
      locked: attr(el, :isLocked) == "true",
      group: group,
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
      nil ->
        %{}

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
      nil ->
        []

      mats_el ->
        find_elements(mats_el)
        |> Enum.map(&parse_material/1)
    end
  end

  defp parse_material(el) do
    case elem(el, 1) do
      :git -> parse_git_material(el)
      :pipeline -> parse_pipeline_material(el)
      :svn -> parse_svn_material(el)
      other -> %{type: to_string(other), url: to_string(attr(el, :url) || "")}
    end
  end

  defp parse_git_material(el) do
    %{
      type: "git",
      url: to_string(attr(el, :url)),
      branch: to_string(attr(el, :branch) || "master"),
      name: to_string(attr(el, :materialName) || attr(el, :dest) || attr(el, :url)),
      auto_update: attr(el, :autoUpdate) != "false"
    }
  end

  defp parse_pipeline_material(el) do
    %{
      type: "dependency",
      pipeline_name: to_string(attr(el, :pipelineName)),
      stage_name: to_string(attr(el, :stageName) || "build"),
      name: to_string(attr(el, :materialName) || attr(el, :pipelineName))
    }
  end

  defp parse_svn_material(el) do
    %{
      type: "svn",
      url: to_string(attr(el, :url)),
      name: to_string(attr(el, :materialName) || attr(el, :dest) || attr(el, :url)),
      username: svn_attr_str(el, :username),
      auto_update: attr(el, :autoUpdate) != "false",
      type_specific_config: %{
        "check_externals" => attr(el, :checkexternals) == "true",
        "password" => to_string(attr(el, :password) || "")
      }
    }
  end

  defp parse_env_vars(el) do
    find_child(el, :environmentvariables)
    |> case do
      nil ->
        %{}

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
      nil ->
        %{}

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
      nil ->
        []

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
      approval_type:
        find_child(el, :approval)
        |> case do
          nil -> "success"
          a -> to_string(attr(a, :type) || "success")
        end,
      environment_variables: parse_env_vars(el),
      secure_variables: parse_secure_vars(el),
      jobs: parse_jobs(el)
    }
  end

  defp parse_jobs(el) do
    find_child(el, :jobs)
    |> case do
      nil ->
        []

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
      tasks: parse_tasks(el),
      tabs: parse_tabs(el),
      artifact_configs: parse_artifacts(el)
    }
  end

  defp parse_resources(el) do
    find_child(el, :resources)
    |> case do
      nil ->
        []

      res_el ->
        find_elements(res_el, :resource) |> Enum.map(fn r -> text_content(r) |> to_string() end)
    end
  end

  defp parse_tabs(el) do
    find_child(el, :tabs)
    |> case do
      nil ->
        %{}

      tabs_el ->
        find_elements(tabs_el, :tab)
        |> Enum.reduce(%{}, fn tab_el, acc ->
          name = to_string(attr(tab_el, :name))
          path = to_string(attr(tab_el, :path))
          if name != "" and path != "", do: Map.put(acc, name, path), else: acc
        end)
    end
  end

  defp parse_artifacts(el) do
    find_child(el, :artifacts)
    |> case do
      nil ->
        %{}

      arts_el ->
        configs =
          find_elements(arts_el, :artifact)
          |> Enum.map(fn art_el ->
            type = to_string(attr(art_el, :type))
            src = to_string(attr(art_el, :src))
            dest = to_string(attr(art_el, :dest))
            %{"type" => type, "src" => src, "dest" => dest}
          end)

        %{"artifacts" => configs}
    end
  end

  defp parse_tasks(el) do
    find_child(el, :tasks)
    |> case do
      nil ->
        []

      tasks_el ->
        find_elements(tasks_el)
        |> Enum.map(&parse_task/1)
    end
  end

  defp parse_task(el) do
    case elem(el, 1) do
      :exec -> parse_exec_task(el)
      :fetchartifact -> parse_fetch_task(el)
      other -> %{type: "exec", command: "echo", args: ["unknown task: #{other}"]}
    end
  end

  defp parse_exec_task(el) do
    command = to_string(attr(el, :command) || "")
    args = find_elements(el, :arg) |> Enum.map(fn a -> text_content(a) |> to_string() end)
    runif_el = find_child(el, :runif)
    runif = if runif_el, do: to_string(attr(runif_el, :status) || "passed"), else: "passed"
    %{type: "exec", command: command, args: args, run_if: [runif]}
  end

  defp parse_fetch_task(el) do
    %{
      type: "fetch",
      pipeline: to_string(attr(el, :pipeline) || ""),
      stage: to_string(attr(el, :stage) || ""),
      job: to_string(attr(el, :job) || ""),
      src_file: to_string(attr(el, :srcfile) || ""),
      dest: to_string(attr(el, :dest) || ""),
      artifact_origin: to_string(attr(el, :artifactOrigin) || "gocd")
    }
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
    |> Enum.find_value(nil, fn a ->
      if elem(a, 1) == name, do: elem(a, 8) |> to_string(), else: nil
    end)
  end

  defp text_content(el) do
    el
    |> elem(8)
    |> Enum.find_value("", fn
      child when elem(child, 0) == :xmlText -> elem(child, 4) |> to_string()
      _ -> nil
    end)
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

  # ── SVN-specific helpers ────────────────────────────────────────────

  defp svn_attr_str(el, name) do
    case attr(el, name) do
      "" -> nil
      nil -> nil
      val -> to_string(val)
    end
  end

  defp maybe_put_attr(map, _key, nil), do: map
  defp maybe_put_attr(map, _key, ""), do: map
  defp maybe_put_attr(map, _key, false), do: map
  defp maybe_put_attr(map, key, value), do: Map.put(map, key, value)

  # ── Extended config sections (GoCD parity: full cruise-config) ─────

  defp render_templates do
    alias ExGoCD.Pipelines.Template

    templates = Repo.all(Template) |> Repo.preload(:pipelines)

    if Enum.empty?(templates) do
      ""
    else
      tag3(
        "templates",
        %{},
        Enum.map_join(templates, "\n", fn t ->
          stages_xml = render_template_stages(t.stages || [])
          tag3("pipeline", %{name: t.name, template: true}, stages_xml)
        end)
      )
    end
  end

  defp render_template_stages(stages) do
    Enum.map_join(stages, "", fn s ->
      name = s["name"] || s[:name] || ""
      jobs = s["jobs"] || s[:jobs] || []

      jobs_xml =
        Enum.map_join(jobs, "", fn j -> tag2("job", %{name: j["name"] || j[:name] || ""}) end)

      tag3("stage", %{name: name}, tag3("jobs", %{}, jobs_xml))
    end)
  end

  defp render_environments do
    alias ExGoCD.Environments.Environment

    envs = Repo.all(Environment)

    if Enum.empty?(envs) do
      ""
    else
      tag3(
        "environments",
        %{},
        Enum.map_join(envs, "\n", fn e ->
          pipelines_xml =
            (e.pipelines || [])
            |> Enum.map_join("", fn p ->
              tag2("pipeline", %{name: p["name"] || p[:name] || ""})
            end)

          tag3("environment", %{name: e.name}, pipelines_xml)
        end)
      )
    end
  end

  defp render_security do
    alias ExGoCD.Accounts.Role
    alias ExGoCD.Repo

    roles = Repo.all(Role)

    if Enum.empty?(roles) do
      ""
    else
      tag3(
        "security",
        %{},
        tag3(
          "roles",
          %{},
          Enum.map_join(roles, "\n", fn r ->
            users_xml =
              (r.users || [])
              |> Enum.map_join("", fn u -> tag2("user", %{name: u}) end)

            tag3("role", %{name: r.name}, users_xml)
          end)
        )
      )
    end
  rescue
    _ -> ""
  end

  defp render_elastic_profiles do
    profiles = ExGoCD.ElasticAgentProfiles.list_profiles()

    if profiles == [] do
      ""
    else
      profiles_xml =
        Enum.map_join(profiles, "\n", fn p ->
          props = p.properties || %{}

          kv_pairs =
            props
            |> Enum.reject(fn {_k, v} -> is_nil(v) || v == %{} || v == [] end)
            |> Enum.map(fn {k, v} -> property_kv_xml(k, v) end)
            |> Enum.join("\n")

          tag3(
            "agentProfile",
            %{
              name: p.name,
              pluginId: p.plugin_id,
              clusterProfileId: p.cluster_profile_id || ""
            },
            kv_pairs
          )
        end)

      tag3("agentProfiles", %{}, profiles_xml)
    end
  rescue
    _ -> ""
  end

  defp property_kv_xml(k, v) when is_map(v), do: prop_xml(k, Jason.encode!(v))
  defp property_kv_xml(k, v) when is_list(v), do: prop_xml(k, Jason.encode!(v))
  defp property_kv_xml(k, v), do: prop_xml(k, to_string(v))

  defp prop_xml(key, value) do
    tag3("property", %{}, tag3("key", %{}, esc(key)) <> tag3("value", %{}, esc(value)))
  end

  defp render_cluster_profiles do
    # Stub — cluster profiles handled by k8s agent; add when schema stabilizes
    ""
  end
end
