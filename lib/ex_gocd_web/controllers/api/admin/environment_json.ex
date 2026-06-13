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
    secure = Map.get(var, "secure") || Map.get(var, :secure) || false
    base = %{
      "name" => Map.get(var, "name") || Map.get(var, :name),
      "secure" => secure
    }

    if secure do
      enc = Map.get(var, "encrypted_value") || Map.get(var, :encrypted_value)
      val = Map.get(var, "value") || Map.get(var, :value)

      enc_val =
        cond do
          enc -> to_string(enc)
          val -> Base.encode64(to_string(val))
          true -> ""
        end

      Map.put(base, "encrypted_value", enc_val)
    else
      Map.put(base, "value", to_string(Map.get(var, "value") || Map.get(var, :value) || ""))
    end
  end

  defp url(path) do
    ExGoCDWeb.Endpoint.url() <> path
  end
end
