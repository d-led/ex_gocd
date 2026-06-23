defmodule ExGoCDWeb.API.Admin.EnvironmentJSON do
  def index(%{environments: environments}) do
    %{
      "_links" => %{
        "self" => %{"href" => url("/go/api/admin/environments")},
        "doc" => %{"href" => "https://api.gocd.org/#environment-config"}
      },
      "_embedded" => %{
        "environments" => Enum.map(environments, &render_environment/1)
      }
    }
  end

  def show(%{environment: environment}) do
    render_environment(environment)
  end

  defp render_environment(env) do
    %{
      "_links" => %{
        "self" => %{"href" => url("/go/api/admin/environments/#{env.name}")},
        "doc" => %{"href" => "https://api.gocd.org/#environment-config"},
        "find" => %{"href" => url("/go/api/admin/environments/:environment_name")}
      },
      "name" => env.name,
      "pipelines" => Enum.map(env.pipelines || [], &render_pipeline/1),
      "environment_variables" => Enum.map(env.environment_variables || [], &render_variable/1)
    }
  end

  defp render_pipeline(pipe) do
    %{
      "_links" => %{
        "self" => %{"href" => url("/go/api/admin/pipelines/#{pipe.name}")},
        "doc" => %{"href" => "https://api.gocd.org/#pipeline-config"},
        "find" => %{"href" => url("/go/api/admin/pipelines/:pipeline_name")}
      },
      "name" => pipe.name
    }
  end

  defp render_variable(var) do
    secure = get_value(var, :secure) || false

    base = %{
      "name" => get_value(var, :name),
      "secure" => secure
    }

    if secure do
      Map.put(base, "encrypted_value", encrypted_value(var))
    else
      Map.put(base, "value", to_string(get_value(var, :value) || ""))
    end
  end

  defp get_value(map, key) do
    Map.get(map, to_string(key)) || Map.get(map, key)
  end

  defp encrypted_value(var) do
    enc = get_value(var, :encrypted_value)
    val = get_value(var, :value)

    cond do
      enc -> to_string(enc)
      val -> Base.encode64(to_string(val))
      true -> ""
    end
  end

  defp url(path) do
    ExGoCDWeb.Endpoint.url() <> path
  end
end
