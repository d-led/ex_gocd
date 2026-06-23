defmodule ExGoCD.Pipelines.ValueStreamMap do
  @moduledoc """
  Calculates Value Stream Maps (VSM) for pipeline instances and SCM materials.
  Bridges DB-backed pipeline runs and development mock-data runs into a
  unified GoCD-compatible structure.
  """

  import Ecto.Query
  alias ExGoCD.MockData
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance}
  alias ExGoCD.Repo

  @doc """
  Generates VSM data for a pipeline name and counter.
  """
  def get_pipeline_vsm(pipeline_name, counter) do
    if counter == 0 do
      build_indeterminate_vsm(pipeline_name)
    else
      if use_mock?(pipeline_name) do
        get_mock_pipeline_vsm(pipeline_name, counter)
      else
        case fetch_db_instance(pipeline_name, counter) do
          nil -> fallback_to_mock_or_not_found(pipeline_name, counter)
          instance -> build_db_pipeline_vsm(instance)
        end
      end
    end
  end

  @doc """
  Generates VSM data for an SCM material fingerprint and revision.
  """
  def get_material_vsm(material_fingerprint, revision) do
    all_mats =
      if use_mock?("") do
        get_all_mock_materials()
      else
        case Pipelines.list_materials() do
          [] -> get_all_mock_materials()
          list -> map_db_materials_vsm(list)
        end
      end

    matching_mat = Enum.find(all_mats, &(fingerprint(&1) == material_fingerprint))
    build_matching_or_generic_vsm(matching_mat, material_fingerprint, revision)
  end

  # Helpers

  defp use_mock?(pipeline_name) do
    System.get_env("USE_MOCK_DATA") == "true" or not has_db_pipeline?(pipeline_name)
  end

  defp has_db_pipeline?(name) do
    if name == "", do: false, else: Repo.exists?(from(p in Pipeline, where: p.name == ^name))
  end

  defp has_mock_pipeline?(name) do
    Enum.any?(MockData.pipelines(), &(&1.name == name))
  end

  defp fetch_db_instance(pipeline_name, counter) do
    from(pi in PipelineInstance,
      join: p in Pipeline, on: pi.pipeline_id == p.id,
      where: p.name == ^pipeline_name and pi.counter == ^counter,
      preload: [stage_instances: :job_instances]
    )
    |> Repo.one()
    |> case do
      nil -> nil
      instance ->
        pipeline = Repo.get(Pipeline, instance.pipeline_id) |> Repo.preload(:materials)
        Map.put(instance, :pipeline_config, pipeline)
    end
  end

  # GoCD parity: counter=0 → EmptyPipelineIdentifier → "indeterminate" VSM
  # Shows pipeline structure but all instances are un-run (counter=0, label="", locator="")
  defp build_indeterminate_vsm(pipeline_name) do
    if use_mock?(pipeline_name) do
      build_mock_indeterminate_vsm(pipeline_name)
    else
      pipeline = Repo.get_by(Pipeline, name: pipeline_name) |> Repo.preload(:materials)
      if is_nil(pipeline) do
        {:error, :not_found}
      else
        build_db_indeterminate_vsm(pipeline)
      end
    end
  end

  defp build_db_indeterminate_vsm(pipeline) do
    pipeline_name = pipeline.name
    materials = pipeline.materials || []
    downstream_names = get_downstream_pipelines(pipeline_name)

    material_nodes = build_material_nodes_no_instance(materials, pipeline_name)
    unrun_instance = build_unrun_instance(pipeline_name)
    fan_in = count_fan_in(pipeline_name)

    pipeline_node = %{
      "id" => pipeline_name,
      "name" => pipeline_name,
      "node_type" => "PIPELINE",
      "depth" => 1,
      "parents" => Enum.map(material_nodes, & &1["id"]),
      "dependents" => downstream_names,
      "fan_in" => fan_in,
      "fan_out" => length(downstream_names),
      "locator" => "/go/pipeline/activity/#{pipeline_name}",
      "can_edit" => true,
      "edit_path" => "/go/admin/pipelines/#{pipeline_name}/edit/general",
      "template_name" => pipeline.template_name,
      "instances" => [unrun_instance]
    }

    downstream_nodes = build_all_downstream_nodes(downstream_names, [pipeline_name], 2)
    levels = assemble_levels(material_nodes, pipeline_node, downstream_nodes)

    {:ok, %{"current_pipeline" => pipeline_name, "levels" => levels}}
  end

  defp build_mock_indeterminate_vsm(pipeline_name) do
    mock_pipeline = Enum.find(MockData.pipelines(), &(&1.name == pipeline_name))
    if is_nil(mock_pipeline) do
      {:error, :not_found}
    else
      materials = mock_pipeline.materials || []
      downstream_names = get_downstream_pipelines(pipeline_name)

      material_nodes =
        materials
        |> Enum.map(fn mat ->
          modification = get_mock_modification(mat)
          build_material_node(mat, modification, pipeline_name)
        end)

      unrun_instance = build_unrun_instance(pipeline_name)

      pipeline_node = %{
        "id" => pipeline_name,
        "name" => pipeline_name,
        "node_type" => "PIPELINE",
        "depth" => 1,
        "parents" => Enum.map(material_nodes, & &1["id"]),
        "dependents" => downstream_names,
        "locator" => "/go/pipeline/activity/#{pipeline_name}",
        "can_edit" => true,
        "edit_path" => "/go/admin/pipelines/#{pipeline_name}/edit/general",
        "template_name" => nil,
        "instances" => [unrun_instance]
      }

      downstream_nodes = build_all_downstream_nodes(downstream_names, [pipeline_name], 2)
      downstream_levels =
        downstream_nodes
        |> Enum.group_by(& &1["depth"])
        |> Enum.sort_by(fn {depth, _nodes} -> depth end)
        |> Enum.map(fn {_depth, nodes} -> %{"nodes" => nodes} end)

      levels = [
        %{"nodes" => material_nodes},
        %{"nodes" => [pipeline_node]}
      ] ++ downstream_levels

      {:ok, %{"current_pipeline" => pipeline_name, "levels" => levels}}
    end
  end

  defp build_material_nodes_no_instance(materials, pipeline_name) do
    Enum.map(materials, fn mat ->
      modification = get_mock_modification(mat)
      build_material_node(mat, modification, pipeline_name)
    end)
  end

  defp build_db_pipeline_vsm(instance) do
    pipeline_name = instance.pipeline_config.name
    materials = instance.pipeline_config.materials || []
    downstream_names = get_downstream_pipelines(pipeline_name)

    material_nodes = build_material_nodes(materials, instance, pipeline_name)
    stages = build_stages_list(instance, pipeline_name)
    fan_in = count_fan_in(pipeline_name)

    pipeline_node = build_pipeline_node(pipeline_name, instance, material_nodes, downstream_names, stages, fan_in, materials)
    downstream_nodes = build_all_downstream_nodes(downstream_names, [pipeline_name], 2)
    levels = assemble_levels(material_nodes, pipeline_node, downstream_nodes)

    {:ok, %{"current_pipeline" => pipeline_name, "levels" => levels}}
  end

  defp build_material_nodes(materials, instance, pipeline_name) do
    Enum.map(materials, fn mat ->
      modification = get_db_or_mock_modification(mat, instance)
      build_material_node(mat, modification, pipeline_name)
    end)
  end

  # GoCD parity: when result is nil/empty (stage still running), use "Unknown".
  # `Map.get(si, :result) || si.state` leaks lifecycle state like "Building"
  # into VSM display. GoCD uses StageResult.Unknown for non-terminal stages.
  defp stage_status_for_vsm(si) do
    case Map.get(si, :result) do
      nil -> "Unknown"
      "" -> "Unknown"
      r -> r
    end
  end

  defp build_stages_list(instance, pipeline_name) do
    (instance.stage_instances || [])
    |> Enum.sort_by(& &1.order_id)
    |> Enum.map(fn si ->
      duration =
        if si.completed_at && si.created_time do
          diff_time(si.completed_at, si.created_time)
        else
          45
        end
      %{
        "name" => si.name,
        "status" => Map.get(si, :result) || si.state,
        "duration" => duration,
        "locator" => "/pipelines/#{pipeline_name}/#{instance.counter}/#{si.name}/#{si.counter}"
      }
    end)
  end

  defp build_pipeline_node(pipeline_name, instance, material_nodes, downstream_names, stages, fan_in, materials) do
    %{
      "id" => pipeline_name,
      "name" => pipeline_name,
      "node_type" => "PIPELINE",
      "depth" => 1,
      "parents" => Enum.map(material_nodes, & &1["id"]),
      "dependents" => downstream_names,
      "fan_in" => fan_in,
      "fan_out" => length(downstream_names),
      "locator" => "/go/pipeline/activity/#{pipeline_name}",
      "can_edit" => true,
      "edit_path" => "/go/admin/pipelines/#{pipeline_name}/edit/general",
      "template_name" => instance.pipeline_config.template_name,
      "instances" => [
        %{
          "label" => instance.label,
          "counter" => instance.counter,
          "locator" => "/pipelines/value_stream_map/#{pipeline_name}/#{instance.counter}",
          "stages" => stages,
          "trigger_info" => %{
            "triggered_by" => Map.get(instance, :trigger_message) || instance.label || "Manual",
            "triggered_at" => instance.inserted_at && Calendar.strftime(instance.inserted_at, "%d %b %Y, %H:%M:%S"),
            "materials" => Enum.map(materials, fn m ->
              %{
                "type" => m.type || "git",
                "url" => m.url,
                "branch" => Map.get(m, :branch) || "main"
              }
            end)
          }
        }
      ]
    }
  end

  defp assemble_levels(material_nodes, pipeline_node, downstream_nodes) do
    downstream_levels =
      downstream_nodes
      |> Enum.group_by(& &1["depth"])
      |> Enum.sort_by(fn {depth, _nodes} -> depth end)
      |> Enum.map(fn {_depth, nodes} -> %{"nodes" => nodes} end)

    [%{"nodes" => material_nodes}, %{"nodes" => [pipeline_node]}] ++ downstream_levels
  end

  defp get_mock_pipeline_vsm(pipeline_name, counter) do
    mock_pipeline = Enum.find(MockData.pipelines(), &(&1.name == pipeline_name))
    if is_nil(mock_pipeline) do
      {:error, :not_found}
    else
      materials = mock_pipeline.materials || []
      downstream_names = get_downstream_pipelines(pipeline_name)

      # Level 0 SCM Materials
      material_nodes =
        materials
        |> Enum.map(fn mat ->
          modification = get_mock_modification(mat)
          build_material_node(mat, modification, pipeline_name)
        end)

      # Target Pipeline node
      stages =
        (mock_pipeline.stages || [])
        |> Enum.map(fn s ->
          %{
            "name" => s.name,
            "status" => s.status,
            "duration" => s.duration || 120,
            "locator" => "/pipelines/#{pipeline_name}/#{counter}/#{s.name}/1"
          }
        end)

      pipeline_node = %{
        "id" => pipeline_name,
        "name" => pipeline_name,
        "node_type" => "PIPELINE",
        "depth" => 1,
        "parents" => Enum.map(material_nodes, & &1["id"]),
        "dependents" => downstream_names,
        "locator" => "/go/pipeline/activity/#{pipeline_name}",
        "can_edit" => true,
        "edit_path" => "/go/admin/pipelines/#{pipeline_name}/edit/general",
        "template_name" => nil,
        "instances" => [
          %{
            "label" => to_string(counter),
            "counter" => counter,
            "locator" => "/pipelines/value_stream_map/#{pipeline_name}/#{counter}",
            "stages" => stages
          }
        ]
      }

      # Level 2 Downstream Pipelines recursively
      downstream_nodes = build_all_downstream_nodes(downstream_names, [pipeline_name], 2)

      downstream_levels =
        downstream_nodes
        |> Enum.group_by(& &1["depth"])
        |> Enum.sort_by(fn {depth, _nodes} -> depth end)
        |> Enum.map(fn {_depth, nodes} -> %{"nodes" => nodes} end)

      levels = [
        %{"nodes" => material_nodes},
        %{"nodes" => [pipeline_node]}
      ] ++ downstream_levels

      {:ok, %{
        "current_pipeline" => pipeline_name,
        "levels" => levels
      }}
    end
  end

  defp build_material_vsm_data(mat, fingerprint, revision) do
    modification = get_mock_modification(mat) |> Map.put(:revision, revision)

    # Level 0 (SCM Material Node)
    material_node = %{
      "id" => fingerprint,
      "name" => mat.url || mat.type,
      "node_type" => "MATERIAL",
      "material_type" => mat.type,
      "depth" => 0,
      "parents" => [],
      "dependents" => mat.pipelines,
      "material_names" => [mat.url || mat.type],
      "material_revisions" => [
        %{
          "modifications" => [
            %{
              "revision" => revision,
              "user" => "#{modification.username} <#{modification.email}>",
              "comment" => modification.comment,
              "modified_time" => format_time_fuzzy(modification.modified_time),
              "locator" => "/materials/value_stream_map/#{fingerprint}/#{revision}"
            }
          ]
        }
      ]
    }

    # Level 1 (Dependent Pipelines)
    pipeline_nodes =
      mat.pipelines
      |> Enum.map(fn name ->
        instance_stages = get_pipeline_stages(name)

        %{
          "id" => name,
          "name" => name,
          "node_type" => "PIPELINE",
          "depth" => 1,
          "parents" => [fingerprint],
          "dependents" => get_downstream_pipelines(name),
          "instances" => [
            %{
              "label" => "1",
              "counter" => 1,
              "locator" => "/pipelines/value_stream_map/#{name}/1",
              "stages" => instance_stages
            }
          ]
        }
      end)

    # Recurse from depth 2 using the dependent pipeline names as parents
    next_names = Enum.flat_map(pipeline_nodes, & &1["dependents"]) |> Enum.uniq()
    downstream_nodes = build_all_downstream_nodes(next_names, mat.pipelines, 2)

    downstream_levels =
      downstream_nodes
      |> Enum.group_by(& &1["depth"])
      |> Enum.sort_by(fn {depth, _nodes} -> depth end)
      |> Enum.map(fn {_depth, nodes} -> %{"nodes" => nodes} end)

    levels = [
      %{"nodes" => [material_node]},
      %{"nodes" => pipeline_nodes}
    ] ++ downstream_levels

    {:ok, %{
      "current_material" => fingerprint,
      "levels" => levels
    }}
  end

  defp get_downstream_pipelines(pipeline_name) do
    db_downstream =
      if use_mock?(pipeline_name) do
        []
      else
        Repo.all(
          from p in Pipeline,
            join: m in assoc(p, :materials),
            where: m.type == "dependency" and m.url == ^pipeline_name,
            select: p.name
        )
      end

    mock_downstream =
      case pipeline_name do
        "build-linux" -> ["deploy-staging"]
        "deploy-staging" -> ["deploy-production"]
        "upstream-lib" -> ["component-a", "component-b", "downstream-app"]
        "component-a" -> ["integration-pipeline"]
        "component-b" -> ["integration-pipeline"]
        _ -> []
      end

    (db_downstream ++ mock_downstream) |> Enum.uniq()
  end

  # Counts how many distinct upstream pipelines feed into the given pipeline.
  # Fan-in > 1 means multiple pipelines converge here.
  def count_fan_in(pipeline_name) do
    db_upstream =
      if use_mock?(pipeline_name) do
        []
      else
        Repo.all(
          from p in Pipeline,
            join: m in assoc(p, :materials),
            where: m.type == "dependency" and m.url == ^pipeline_name,
            select: p.name
        )
      end

    mock_upstream =
      case pipeline_name do
        "deploy-staging" -> ["build-linux"]
        "deploy-production" -> ["deploy-staging"]
        "component-a" -> ["upstream-lib"]
        "component-b" -> ["upstream-lib"]
        "integration-pipeline" -> ["component-a", "component-b"]
        "downstream-app" -> ["upstream-lib"]
        _ -> []
      end

    (db_upstream ++ mock_upstream) |> Enum.uniq() |> length()
  end

  defp build_all_downstream_nodes(names, parents, depth, visited \\ MapSet.new())
  defp build_all_downstream_nodes([], _parents, _depth, _visited), do: []
  defp build_all_downstream_nodes(names, parents, depth, visited) do
    unvisited_names = Enum.reject(names, &MapSet.member?(visited, &1))
    if Enum.empty?(unvisited_names) do
      []
    else
      new_visited = Enum.reduce(unvisited_names, visited, &MapSet.put(&2, &1))

      nodes =
        unvisited_names
        |> Enum.map(fn name ->
          downstream = get_downstream_pipelines(name)

          instance_data = get_downstream_instance_data(name, parents)

          %{
            "id" => name,
            "name" => name,
            "node_type" => "PIPELINE",
            "depth" => depth,
            "parents" => parents,
            "dependents" => downstream,
            "instances" => [instance_data]
          }
        end)

      next_parents = unvisited_names
      next_names = Enum.flat_map(nodes, & &1["dependents"]) |> Enum.uniq()

      nodes ++ build_all_downstream_nodes(next_names, next_parents, depth + 1, new_visited)
    end
  end

  @doc """
  Returns VSM instance data for a downstream pipeline node.
  Looks up the actual PipelineInstance triggered by any of the parent pipelines.
  Falls back to un-run stages if no instance found.
  """
  def get_downstream_instance_data(name, parents) when is_list(parents) do
    case find_triggered_instance(name, parents) do
      nil -> build_unrun_instance(name)
      instance -> build_real_instance(instance)
    end
  end

  defp find_triggered_instance(name, parents) do
    from(pi in PipelineInstance,
      join: p in assoc(pi, :pipeline),
      where: p.name == ^name,
      order_by: [desc: pi.counter],
      limit: 5,
      preload: [:pipeline, stage_instances: :job_instances]
    )
    |> Repo.all()
    |> Enum.find(fn pi ->
      bc = pi.build_cause || %{}
      revisions = bc["materialRevisions"] || []
      Enum.any?(revisions, fn rev ->
        mat = rev["material"] || rev
        mat_type = mat["type"] || rev["material_type"] || rev["type"]
        mat_url = mat["url"] || rev["url"] || rev["pipeline_name"] || rev["name"]
        mat_type == "dependency" && Enum.member?(parents, mat_url)
      end)
    end)
  end

  defp build_real_instance(instance) do
    pipeline_name =
      case instance.pipeline do
        %Ecto.Association.NotLoaded{} ->
          # Fallback: extract pipeline name from build_cause or just use stage instance names
          instance.stage_instances |> List.first() |> Map.get(:name) || "unknown"
        pipeline ->
          pipeline.name
      end

    stages =
      (instance.stage_instances || [])
      |> Enum.sort_by(& &1.order_id)
      |> Enum.map(fn si ->
        %{
          "name" => si.name,
          "status" => stage_status_for_vsm(si),
          "duration" => diff_time(si.completed_at, si.created_time),
          "locator" => "/pipelines/#{pipeline_name}/#{instance.counter}/#{si.name}/#{si.counter}"
        }
      end)

    %{
      "label" => instance.label,
      "counter" => instance.counter,
      "locator" => "/pipelines/value_stream_map/#{pipeline_name}/#{instance.counter}",
      "stages" => stages
    }
  end

  # GoCD parity: EmptyPipelineIdentifier → counter=0, label=""
  # UnrunPipelineRevision → counter=0 means "never run" / indeterminate
  defp build_unrun_instance(name) do
    %{
      "label" => "",
      "counter" => 0,
      "locator" => "",
      "stages" => get_pipeline_stages(name)
    }
  end

  defp get_db_or_mock_modification(mat, instance) do
    cause = instance.build_cause || %{}
    revisions = cause["materialRevisions"] || []

    case Enum.find(revisions, &(&1["url"] == mat.url)) do
      nil -> get_mock_modification(mat)
      rev -> get_modification_from_rev(rev, mat)
    end
  end

  defp get_modification_from_rev(rev, mat) do
    case List.first(rev["modifications"] || []) do
      nil ->
        get_mock_modification(mat)

      mod ->
        %{
          username: mod["username"] || "anonymous",
          email: mod["email"] || "",
          revision: mod["revision"] || "unknown",
          comment: mod["comment"] || "",
          modified_time: parse_or_default_time(mod["modifiedTime"])
        }
    end
  end

  defp parse_or_default_time(nil), do: DateTime.utc_now()
  defp parse_or_default_time(time_str) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_or_default_time(_), do: DateTime.utc_now()

  defp get_mock_modification(mat) do
    cond do
      String.contains?(mat.url || "", "gocd/gocd") ->
        %{
          username: "Dmitry Ledentsov",
          email: "dmlled@yahoo.com",
          revision: "05172d07f4f4a0765243628b94f6840f8dc5411a",
          comment: "upgrade actions and fix compilation warnings",
          modified_time: ~U[2026-06-11 12:00:00Z]
        }
      String.contains?(mat.url || "", "gocd/docs") ->
        %{
          username: "ExGoCD Team",
          email: "dev@exgocd.local",
          revision: "98a7b6c5d4e3f2a10987654321abcdef01234567",
          comment: "Update materials page documentation for rewrite",
          modified_time: ~U[2026-06-11 11:30:00Z]
        }
      true ->
        %{
          username: "exgocd-admin",
          email: "admin@exgocd.local",
          revision: "f0e1d2c3b4a5968776655443322110abcdef0123",
          comment: "Initial commit for repository integration",
          modified_time: ~U[2026-06-11 10:15:00Z]
        }
    end
  end

  defp fingerprint(mat) do
    :crypto.hash(:sha256, "#{mat.type}-#{mat.url || ""}-#{Map.get(mat, :branch) || ""}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp format_time_fuzzy(_time) do
    "2 hours ago"
  end

  defp diff_time(completed_at, created_time) do
    c_dt = to_utc_datetime(completed_at)
    cr_dt = to_utc_datetime(created_time)
    if c_dt && cr_dt, do: DateTime.diff(c_dt, cr_dt, :second), else: 45
  end

  defp to_utc_datetime(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")
  defp to_utc_datetime(%NaiveDateTime{} = ndt) do
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, dt} -> dt
      _ -> nil
    end
  end
  defp to_utc_datetime(_), do: nil

  defp get_all_mock_materials do
    MockData.get_all_mock_materials()
  end

  defp fallback_to_mock_or_not_found(pipeline_name, counter) do
    if has_mock_pipeline?(pipeline_name) do
      get_mock_pipeline_vsm(pipeline_name, counter)
    else
      {:error, :not_found}
    end
  end

  defp map_db_materials_vsm(list) do
    Enum.map(list, fn m ->
      %{
        type: m.type,
        url: m.url,
        branch: m.branch,
        pipelines: Enum.map(m.pipelines || [], & &1.name)
      }
    end)
  end

  defp build_matching_or_generic_vsm(nil, material_fingerprint, revision) do
    # Fallback: unknown fingerprint — return basic git material placeholder
    generic_mat = %{
      type: "git",
      url: "https://github.com/d-led/ex_gocd.git",
      branch: "main",
      pipelines: []
    }
    build_material_vsm_data(generic_mat, material_fingerprint, revision)
  end

  defp build_matching_or_generic_vsm(matching_mat, material_fingerprint, revision) do
    build_material_vsm_data(matching_mat, material_fingerprint, revision)
  end

  # Returns stages for a pipeline node in the VSM.
  # ONLY called from build_unrun_instance → always returns un-run stages.
  # GoCD parity: UnrunStagesPopulator adds NullStage (status=Unknown) for each configured stage.
  defp get_pipeline_stages(name) do
    if use_mock?(name) do
      mock_pipeline = Enum.find(MockData.pipelines(), &(&1.name == name))
      if mock_pipeline && mock_pipeline.stages do
        Enum.map(mock_pipeline.stages, fn s ->
          %{"name" => s.name, "status" => "Unknown", "duration" => 0, "locator" => ""}
        end)
      else
        [%{"name" => "build", "status" => "Unknown", "duration" => 0, "locator" => ""}]
      end
    else
      pipeline = Repo.get_by(Pipeline, name: name) |> Repo.preload(stages: [jobs: :tasks])

      if pipeline && pipeline.stages do
        Enum.map(pipeline.stages, fn stage ->
          %{
            "name" => stage.name,
            "status" => "Unknown",
            "duration" => 0,
            "locator" => ""
          }
        end)
      else
        []
      end
    end
  end

  defp build_material_node(mat, modification, pipeline_name) do
    fp = fingerprint(mat)
    %{
      "id" => fp,
      "name" => mat.url || mat.type,
      "node_type" => "MATERIAL",
      "material_type" => mat.type,
      "depth" => 0,
      "parents" => [],
      "dependents" => [pipeline_name],
      "material_names" => [mat.url || mat.type],
      "material_revisions" => [
        %{
          "modifications" => [
            %{
              "revision" => modification.revision,
              "user" => "#{modification.username} <#{modification.email}>",
              "comment" => modification.comment,
              "modified_time" => format_time_fuzzy(modification.modified_time),
              "locator" => "/materials/value_stream_map/#{fp}/#{modification.revision}"
            }
          ]
        }
      ]
    }
  end
end
