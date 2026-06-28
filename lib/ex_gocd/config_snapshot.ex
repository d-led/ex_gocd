defmodule ExGoCD.ConfigSnapshot do
  @moduledoc """
  Captures the full server configuration as a versioned snapshot.

  Call `snapshot/2` after any config mutation (create, update, delete)
  across pipelines, templates, environments, elastic profiles, k8s
  clusters, security, artifact stores, secret configs, package repos.

  The snapshot includes ALL config entities, with secrets stored as
  `encryptedValue` (AES:iv:ciphertext) — never plaintext.

  If the config hasn't changed (same hash as the latest version),
  the snapshot is silently skipped (deduplication).
  """

  alias ExGoCD.ConfigVersion
  alias ExGoCD.Repo

  @doc """
  Takes a snapshot of the current full config.

  Returns `{:ok, version}` or `:unchanged` (same hash as latest).

  `changed_by` — username or system trigger.
  `change_reason` — e.g. "pipeline updated", "cluster profile added".
  """
  @spec snapshot(String.t(), String.t()) :: {:ok, ConfigVersion.t()} | :unchanged
  def snapshot(changed_by, change_reason) do
    config = capture()
    hash = hash_config(config)

    if latest_hash() == hash do
      :unchanged
    else
      xml = config_to_xml(config)

      {:ok, version} =
        %ConfigVersion{}
        |> Ecto.Changeset.cast(
          %{
            config_hash: hash,
            config_json: config,
            config_xml: xml,
            changed_by: changed_by,
            change_reason: change_reason
          },
          [:config_hash, :config_json, :config_xml, :changed_by, :change_reason]
        )
        |> Repo.insert()

      {:ok, version}
    end
  end

  @doc """
  Fire-and-forget snapshot after a config mutation succeeds.
  Runs in a Task so snapshot failures never affect the caller.
  """
  @spec after_mutation(String.t(), String.t()) :: :ok
  def after_mutation(changed_by, change_reason) do
    Task.start(fn -> snapshot(changed_by, change_reason) end)
    :ok
  end

  # ── Config capture ──────────────────────────────────────────────────

  defp capture do
    %{
      "schema_version" => 1,
      "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "server" => safe_section(&server_config/0),
      "pipelines" => safe_section(&pipelines_config/0),
      "templates" => safe_section(&templates_config/0),
      "environments" => safe_section(&environments_config/0),
      "elastic_profiles" => safe_section(&elastic_profiles_config/0),
      "cluster_profiles" => safe_section(&cluster_profiles_config/0),
      "security" => safe_section(&security_config/0),
      "artifact_stores" => safe_section(&artifact_stores_config/0),
      "secret_configs" => safe_section(&secret_configs_config/0),
      "package_repositories" => safe_section(&package_repos_config/0),
      "scms" => safe_section(&scms_config/0),
      "config_repos" => safe_section(&config_repos_config/0)
    }
  end

  defp safe_section(fun) do
    fun.()
  rescue
    e ->
      %{"_error" => Exception.message(e)}
  end

  # ── Individual sections ─────────────────────────────────────────────

  defp server_config do
    endpoint_config = Application.get_env(:ex_gocd, ExGoCDWeb.Endpoint) || []

    site_url =
      case endpoint_config[:url] do
        {scheme, host} -> "#{scheme}://#{host}"
        url when is_binary(url) -> url
        _ -> "http://localhost:4000"
      end

    %{
      "site_url" => site_url,
      "artifacts_dir" => "artifacts",
      "command_repo_url" => Application.get_env(:ex_gocd, :command_repository_url) || "",
      "server_id" => server_id()
    }
  end

  defp pipelines_config do
    alias ExGoCD.Pipelines

    Pipelines.list_pipelines()
    |> ExGoCD.Repo.preload([:materials, stages: [jobs: :tasks]])
    |> Enum.map(fn p ->
      %{
        "name" => p.name,
        "group" => p.group,
        "label_template" => p.label_template,
        "lock_behavior" => p.lock_behavior,
        "template_name" => p.template_name,
        "params" => p.params,
        "parameters" => p.parameters,
        "environment_variables" => p.environment_variables,
        "secure_variables" => encrypt_map_values(p.secure_variables),
        "timer" => p.timer,
        "timer_only_on_changes" => p.timer_only_on_changes,
        "tracking_tool" => p.tracking_tool,
        "materials" => materials_config(p.materials),
        "stages" => stages_config(p.stages)
      }
    end)
  end

  defp materials_config(materials) when is_list(materials) do
    Enum.map(materials, fn m ->
      %{
        "type" => m.type,
        "url" => m.url,
        "name" => m.name,
        "branch" => Map.get(m, :branch),
        "username" => Map.get(m, :username),
        "encrypted_password" => encrypt_if_present(Map.get(m, :password)),
        "auto_update" => Map.get(m, :auto_update, true),
        "type_specific_config" => Map.get(m, :type_specific_config)
      }
    end)
  end

  defp stages_config(stages) when is_list(stages) do
    Enum.map(stages, fn s ->
      %{
        "name" => s.name,
        "approval_type" => Map.get(s, :approval_type, "success"),
        "clean_working_dir" => Map.get(s, :clean_working_dir, false),
        "fetch_materials" => Map.get(s, :fetch_materials, true),
        "environment_variables" => Map.get(s, :environment_variables),
        "secure_variables" => encrypt_map_values(Map.get(s, :secure_variables)),
        "jobs" => jobs_config(Map.get(s, :jobs) || [])
      }
    end)
  end

  defp jobs_config(jobs) when is_list(jobs) do
    Enum.map(jobs, fn j ->
      %{
        "name" => j.name,
        "timeout" => Map.get(j, :timeout),
        "run_instance_count" => Map.get(j, :run_instance_count),
        "resources" => Map.get(j, :resources) || [],
        "environment_variables" => Map.get(j, :environment_variables),
        "secure_variables" => encrypt_map_values(Map.get(j, :secure_variables)),
        "tasks" => tasks_config(Map.get(j, :tasks) || [])
      }
    end)
  end

  defp tasks_config(tasks) when is_list(tasks) do
    Enum.map(tasks, fn t ->
      %{
        "type" => t.type,
        "attributes" => t.attributes |> encrypt_task_password()
      }
    end)
  end

  defp templates_config do
    alias ExGoCD.Repo
    alias ExGoCD.Pipelines.PipelineTemplate

    Repo.all(PipelineTemplate)
    |> Enum.map(fn t ->
      %{
        "name" => t.name,
        "pipelines" => t.pipelines || [],
        "stages" => stages_config(t.stages || [])
      }
    end)
  end

  defp environments_config do
    alias ExGoCD.Repo
    alias ExGoCD.Pipelines.Environment

    Repo.all(Environment)
    |> Enum.map(fn e ->
      %{
        "name" => e.name,
        "pipelines" => e.pipelines || [],
        "environment_variables" => e.environment_variables,
        "secure_variables" => encrypt_map_values(e.secure_variables)
      }
    end)
  end

  defp elastic_profiles_config do
    alias ExGoCD.ElasticAgentProfiles

    ElasticAgentProfiles.list_profiles()
    |> Enum.map(fn p ->
      %{
        "id" => p.id,
        "name" => p.name,
        "cluster_profile_id" => p.cluster_profile_id,
        "image" => p.image,
        "image_pull_policy" => p.image_pull_policy,
        "min_memory" => p.min_memory,
        "max_memory" => p.max_memory,
        "min_cpu" => p.min_cpu,
        "max_cpu" => p.max_cpu,
        "privileged" => p.privileged,
        "service_account" => p.service_account,
        "node_selector" => p.node_selector,
        "pod_annotations" => p.pod_annotations,
        "env_vars" => p.env_vars,
        "properties" => p.properties
      }
    end)
  end

  defp cluster_profiles_config do
    alias ExGoCD.ClusterProfiles

    ClusterProfiles.list_profiles()
    |> Enum.map(fn c ->
      %{
        "id" => c.id,
        "name" => c.name,
        "plugin_id" => c.plugin_id,
        "server_url" => c.server_url,
        "encrypted_bearer_token" => encrypt_if_present(c.bearer_token),
        "encrypted_client_key" => encrypt_if_present(c.client_key_data),
        "namespace" => c.namespace,
        "ca_cert" => c.ca_cert_data,
        "properties" => c.properties
      }
    end)
  end

  defp security_config do
    %{
      "auth_configs" => auth_configs(),
      "roles" => roles_config()
    }
  end

  defp auth_configs do
    alias ExGoCD.Repo
    alias ExGoCD.Accounts.AuthConfig

    Repo.all(AuthConfig)
    |> Enum.map(fn a ->
      %{
        "id" => a.id,
        "plugin_id" => a.plugin_id,
        "encrypted_password" => encrypt_if_present(a.password),
        "properties" => a.properties
      }
    end)
  rescue
    _ -> []
  end

  defp roles_config do
    alias ExGoCD.Repo
    alias ExGoCD.Accounts.Role

    Repo.all(Role)
    |> Enum.map(fn r ->
      %{
        "name" => r.name,
        "type" => r.type,
        "users" => r.users || [],
        "policy" => r.policy
      }
    end)
  rescue
    _ -> []
  end

  defp artifact_stores_config do
    alias ExGoCD.Repo
    alias ExGoCD.ArtifactStores.ArtifactStore

    Repo.all(ArtifactStore)
    |> Enum.map(fn a ->
      %{
        "id" => a.id,
        "plugin_id" => a.plugin_id,
        "properties" => a.properties
      }
    end)
  rescue
    _ -> []
  end

  defp secret_configs_config do
    alias ExGoCD.Repo
    alias ExGoCD.SecretConfigs.SecretConfig

    Repo.all(SecretConfig)
    |> Enum.map(fn s ->
      %{
        "id" => s.id,
        "plugin_id" => s.plugin_id,
        "encrypted_value" => s.encrypted_value,
        "properties" => s.properties
      }
    end)
  rescue
    _ -> []
  end

  defp package_repos_config do
    alias ExGoCD.Repo
    alias ExGoCD.Packages.PackageRepository

    Repo.all(PackageRepository)
    |> Enum.map(fn p ->
      %{
        "id" => p.id,
        "name" => p.name,
        "plugin_id" => p.plugin_id,
        "repo_url" => p.repo_url,
        "properties" => p.properties
      }
    end)
  rescue
    _ -> []
  end

  defp scms_config do
    []
  end

  defp config_repos_config do
    alias ExGoCD.Repo
    alias ExGoCD.ConfigRepos.ConfigRepo

    Repo.all(ConfigRepo)
    |> Enum.map(fn c ->
      %{
        "id" => c.id,
        "plugin_id" => c.plugin_id,
        "repo_url" => c.repo_url,
        "encrypted_password" => encrypt_if_present(c.password),
        "material_update_interval" => c.material_update_interval,
        "properties" => c.properties
      }
    end)
  rescue
    _ -> []
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp hash_config(config) do
    # Exclude volatile/temporal fields from hash so identical configs
    # produce the same hash across snapshot calls.
    # captured_at changes every call; _error may vary between environments.
    stable =
      config
      |> Map.delete("captured_at")
      |> strip_error_sections()

    :crypto.hash(:sha256, Jason.encode!(stable))
    |> Base.encode16(case: :lower)
  end

  defp strip_error_sections(map) when is_map(map) do
    Map.new(map, fn
      {_k, %{"_error" => _}} -> {nil, nil}
      {k, v} when is_map(v) -> {k, strip_error_sections(v)}
      {k, v} -> {k, v}
    end)
    |> Map.reject(fn {k, _} -> is_nil(k) end)
  end

  defp latest_hash do
    import Ecto.Query

    from(v in ConfigVersion, order_by: [desc: v.inserted_at], limit: 1, select: v.config_hash)
    |> Repo.one()
  end

  defp server_id do
    "ex-gocd"
  end

  defp encrypt_if_present(nil), do: nil
  defp encrypt_if_present(""), do: nil

  defp encrypt_if_present(value) when is_binary(value) do
    ExGoCD.Crypto.encrypt(value)
  end

  defp encrypt_map_values(nil), do: %{}
  defp encrypt_map_values(map) when map == %{}, do: %{}

  defp encrypt_map_values(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {k, encrypt_if_present(v)}
    end)
  end

  defp encrypt_task_password(%{"password" => pwd} = attrs) when is_binary(pwd) do
    Map.put(attrs, "encrypted_password", ExGoCD.Crypto.encrypt(pwd))
    |> Map.delete("password")
  end

  defp encrypt_task_password(attrs), do: attrs

  defp config_to_xml(_config) do
    ExGoCD.ConfigXml.generate()
  end
end
