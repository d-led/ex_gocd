defmodule ExGoCD.Mcp.Tools.Config do
  @moduledoc """
  The server's configuration as a whole: the XML a GoCD administrator would
  keep in version control, the versions this server recorded, the environments
  pipelines are grouped into, and the materials they build from.

  `gocd_config_xml` is the honest answer to "what is configured" — it is the
  same document `ConfigXml.generate/0` writes for the config page and the
  `/go/api/admin/config.xml` endpoint, so an assistant that compares it with a
  checkout is comparing like with like.
  """

  alias ExGoCD.{ConfigVersion, ConfigXml, Environments, Pipelines}
  alias ExGoCD.Mcp.{Args, Render, Tool}

  @names ~w(gocd_config_xml gocd_config_history gocd_environments gocd_materials)

  @tools [
    %{
      "name" => "gocd_config_xml",
      "title" => "The whole configuration as XML",
      "description" =>
        "This server's configuration in GoCD's `cruise-config.xml` shape: pipelines, stages, " <>
          "jobs, tasks, materials, templates, environments, secret configuration names and " <>
          "package repositories. Secret values stay encrypted, as they are stored. Use it to " <>
          "compare a live server with a configuration kept in a repository.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_config_history",
      "title" => "Configuration versions",
      "description" =>
        "The configuration versions this server recorded, newest first: when, by whom, and " <>
          "why. Give `version` to read one whole — its metadata and its XML — which is how to " <>
          "find what the configuration looked like before a change.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200, "default" => 20},
          "version" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "One version's id."
          }
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_environments",
      "title" => "Environments and their pipelines",
      "description" =>
        "Every environment, the pipelines in it, and its variables (secure ones are named, " <>
          "never shown). Environments are what agents and jobs are matched on, so this is " <>
          "half of the answer to \"can this job run anywhere\".",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_materials",
      "title" => "Materials and their latest revision",
      "description" =>
        "The source materials this server builds from — type, url, branch, destination, " <>
          "filters, fingerprint — the pipelines each feeds, and the latest modification it " <>
          "saw. Filter by words in the url or destination.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Words the url or destination must contain."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500, "default" => 100}
        }
      },
      "annotations" => Tool.read_only()
    }
  ]

  @doc "The definitions of this family's tools."
  @spec definitions() :: [map()]
  def definitions, do: @tools

  @doc "The names of this family's tools."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Whether this family answers to a tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: name in @names

  @doc "Calls one of this family's tools."
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call("gocd_config_xml", args, ctx), do: config_xml(args, ctx)
  def call("gocd_config_history", args, ctx), do: config_history(args, ctx)
  def call("gocd_environments", args, ctx), do: environments(args, ctx)
  def call("gocd_materials", args, ctx), do: materials(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp config_xml(_args, _ctx) do
    xml = ConfigXml.generate()

    Tool.ok(
      "This server's configuration, #{byte_size(xml)} bytes:\n\n" <> xml,
      %{"xml" => xml, "bytes" => byte_size(xml)}
    )
  end

  defp config_history(args, _ctx) do
    with {:ok, limit} <- Args.integer(args, "limit", default: 20, min: 1, max: 200) do
      case args["version"] do
        nil ->
          list_versions(limit)

        _present ->
          one_version(args)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp list_versions(limit) do
    versions = ConfigVersion.recent(limit)

    text =
      "#{ConfigVersion.count()} configuration version(s), showing #{length(versions)}\n\n" <>
        Render.table(
          ["ID", "WHEN", "CHANGED BY", "REASON"],
          Enum.map(versions, fn version ->
            [
              version.id,
              Render.timestamp(version.inserted_at),
              version.changed_by,
              version.change_reason
            ]
          end)
        )

    Tool.ok(text, %{
      "total" => ConfigVersion.count(),
      "versions" =>
        Enum.map(versions, fn version ->
          %{
            "id" => version.id,
            "inserted_at" => Render.timestamp(version.inserted_at),
            "changed_by" => version.changed_by,
            "change_reason" => version.change_reason
          }
        end)
    })
  end

  defp one_version(args) do
    with {:ok, id} <- Args.required_integer(args, "version") do
      case ConfigVersion.get(id) do
        nil ->
          {:error, "Configuration version #{id} not found."}

        version ->
          xml = version.config_xml || "(this version was stored without an XML document)"

          Tool.ok(
            "Version #{version.id} · #{Render.timestamp(version.inserted_at)} · " <>
              "by #{Render.cell(version.changed_by)} · #{Render.cell(version.change_reason)} " <>
              "(#{byte_size(xml)} bytes)\n\n" <> xml,
            %{
              "version" => map_version(version),
              "xml" => version.config_xml
            }
          )
      end
    end
  end

  defp environments(_args, _ctx) do
    environments = Environments.list_environments()

    text =
      if environments == [] do
        "No environments are configured."
      else
        Render.table(
          ["ENVIRONMENT", "PIPELINES", "VARIABLES"],
          Enum.map(environments, fn environment ->
            [
              environment.name,
              Enum.map_join(environment.pipelines || [], ", ", & &1.name),
              Enum.map_join(environment.environment_variables || [], ", ", &variable_label/1)
            ]
          end)
        )
      end

    Tool.ok(text, %{
      "environments" =>
        Enum.map(environments, fn environment ->
          %{
            "name" => environment.name,
            "pipelines" => Enum.map(environment.pipelines || [], & &1.name),
            "variables" => Enum.map(environment.environment_variables || [], &variable_map/1)
          }
        end)
    })
  end

  defp materials(args, _ctx) do
    with {:ok, query} <- Args.optional(args, "query"),
         {:ok, limit} <- Args.integer(args, "limit", default: 100, min: 1, max: 500) do
      materials =
        Pipelines.list_materials()
        |> Enum.filter(&matches?(&1, query))
        |> Enum.sort_by(& &1.url)
        |> Enum.take(limit)

      rows =
        Enum.map(materials, fn material ->
          modification = Pipelines.get_latest_modification(material.id)

          %{
            "type" => material.type,
            "url" => material.url,
            "branch" => material.branch,
            "destination" => material.destination,
            "auto_update" => material.auto_update,
            "fingerprint" => Pipelines.material_fingerprint(material),
            "pipelines" => Enum.map(material.pipelines || [], & &1.name),
            "latest_revision" => modification && modification.revision,
            "latest_modified_at" => modification && Render.timestamp(modification.modified_time),
            "latest_comment" => modification && modification.comment
          }
        end)

      text =
        "#{length(materials)} material(s)\n\n" <>
          Render.table(
            ["TYPE", "URL", "BRANCH", "LATEST REVISION", "MODIFIED", "PIPELINES"],
            Enum.map(rows, fn material ->
              [
                material["type"],
                material["url"],
                material["branch"],
                shorten(material["latest_revision"]),
                material["latest_modified_at"],
                material["pipelines"]
              ]
            end)
          )

      Tool.ok(text, %{"materials" => rows})
    else
      {:error, message} -> {:error, message}
    end
  end

  defp map_version(version) do
    %{
      "id" => version.id,
      "inserted_at" => Render.timestamp(version.inserted_at),
      "changed_by" => version.changed_by,
      "change_reason" => version.change_reason,
      "config_hash" => version.config_hash
    }
  end

  defp variable_label(%{"name" => name} = variable), do: variable_label(to_string(name), variable)
  defp variable_label(%{name: name} = variable), do: variable_label(to_string(name), variable)
  defp variable_label(other), do: inspect(other)

  defp variable_label(name, variable) do
    if Map.get(variable, "secure") || Map.get(variable, :secure) do
      "#{name} (secure)"
    else
      "#{name}=#{Map.get(variable, "value") || Map.get(variable, :value)}"
    end
  end

  defp variable_map(variable) do
    %{
      "name" => Map.get(variable, "name") || Map.get(variable, :name),
      "value" =>
        if(secure?(variable),
          do: nil,
          else: Map.get(variable, "value") || Map.get(variable, :value)
        ),
      "secure" => secure?(variable)
    }
  end

  defp secure?(variable), do: !!(Map.get(variable, "secure") || Map.get(variable, :secure))

  defp matches?(_material, nil), do: true

  defp matches?(material, query) do
    haystack = String.downcase("#{material.url} #{material.destination}")
    String.contains?(haystack, String.downcase(query))
  end

  defp shorten(nil), do: nil
  defp shorten(revision) when is_binary(revision), do: String.slice(revision, 0, 12)
  defp shorten(other), do: other
end
