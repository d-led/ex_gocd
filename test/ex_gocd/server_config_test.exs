defmodule ExGoCD.ServerConfigTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.ServerConfig

  # These tests set the environment a setting falls back to, so they run one at
  # a time rather than off each other's variables.

  describe "site urls" do
    test "a stored URL is what links use, whatever the environment says" do
      with_environment(%{"PHX_URL" => "http://from-the-environment.example"}, fn ->
        {:ok, _} = ServerConfig.update(%{"site_url" => "http://stored.example"})

        assert ServerConfig.site_urls().site_url == "http://stored.example"
      end)
    end

    test "until one is stored, the environment supplies the URL" do
      with_environment(
        %{"PHX_URL" => nil, "SITE_URL" => "http://from-the-environment.example"},
        fn ->
          assert ServerConfig.site_urls().site_url == "http://from-the-environment.example"
        end
      )
    end

    test "the secure URL is the site URL when only that one is set" do
      with_environment(
        %{
          "PHX_URL" => "http://plain.example",
          "PHX_SECURE_URL" => nil,
          "SECURE_SITE_URL" => nil
        },
        fn ->
          assert ServerConfig.site_urls().secure_site_url == "http://plain.example"
        end
      )
    end

    test "clearing a URL hands it back to the environment" do
      with_environment(%{"PHX_URL" => "http://from-the-environment.example"}, fn ->
        {:ok, _} = ServerConfig.update(%{"site_url" => "http://stored.example"})
        {:ok, _} = ServerConfig.update(%{"site_url" => ""})

        assert ServerConfig.site_urls().site_url == "http://from-the-environment.example"
      end)
    end

    test "refuses a site URL that does not start with http or https" do
      assert {:error, changeset} = ServerConfig.update(%{"site_url" => "ci.example"})

      assert errors_on(changeset) == %{
               site_url: ["Invalid format for site url. 'ci.example' must start with http/s"]
             }
    end

    test "refuses a secure site URL that is not https" do
      assert {:error, changeset} =
               ServerConfig.update(%{"secure_site_url" => "http://ci.example"})

      assert errors_on(changeset) == %{
               secure_site_url: [
                 "Invalid format for secure site url. 'http://ci.example' must start with https"
               ]
             }
    end
  end

  describe "the default job timeout" do
    test "is stored as the minutes a job may stay silent" do
      {:ok, _} = ServerConfig.update(%{"default_job_timeout" => "10"})

      assert ServerConfig.default_job_timeout() == "10"
    end

    test "falls back to DEFAULT_JOB_TIMEOUT until one is stored" do
      with_environment(%{"DEFAULT_JOB_TIMEOUT" => "5"}, fn ->
        assert ServerConfig.default_job_timeout() == "5"
      end)
    end

    test "refuses a value that is not a number" do
      assert {:error, changeset} = ServerConfig.update(%{"default_job_timeout" => "ten minutes"})

      assert errors_on(changeset) == %{
               default_job_timeout: [
                 "Timeout should be a valid number as it represents number of minutes"
               ]
             }
    end

    test "refuses a negative number" do
      assert {:error, changeset} = ServerConfig.update(%{"default_job_timeout" => "-1"})

      assert errors_on(changeset) == %{
               default_job_timeout: [
                 "Timeout cannot be a negative number as it represents number of minutes"
               ]
             }
    end
  end

  describe "the artifact config" do
    test "stores the directory and the purge settings together" do
      {:ok, _} =
        ServerConfig.update(%{
          "artifacts_dir" => "/data/artifacts",
          "purge_start_disk_space" => 30,
          "purge_upto_disk_space" => 60
        })

      assert ServerConfig.artifact_config() == %{
               artifacts_dir: "/data/artifacts",
               purge_start_disk_space: 30.0,
               purge_upto_disk_space: 60.0
             }
    end

    test "writing the directory leaves the purge settings as they were" do
      {:ok, _} =
        ServerConfig.update(%{
          "artifacts_dir" => "/data/first",
          "purge_start_disk_space" => 30,
          "purge_upto_disk_space" => 60
        })

      {:ok, _} = ServerConfig.update(%{"artifacts_dir" => "/data/second"})

      assert %{
               artifacts_dir: "/data/second",
               purge_start_disk_space: 30.0,
               purge_upto_disk_space: 60.0
             } = ServerConfig.artifact_config()
    end

    test "refuses an empty directory" do
      assert {:error, changeset} = ServerConfig.update(%{"artifacts_dir" => " "})

      assert errors_on(changeset) == %{
               artifacts_dir: ["Please provide a not empty value for artifactsdir"]
             }
    end

    test "refuses the root of the server's own sandbox" do
      assert {:error, changeset} = ServerConfig.update(%{"artifacts_dir" => "."})

      assert [message] = errors_on(changeset).artifacts_dir
      assert message =~ "artifactsdir should not point to the root of sand box"
    end

    test "refuses a purge goal with no trigger" do
      assert {:error, changeset} = ServerConfig.update(%{"purge_upto_disk_space" => 60})

      assert errors_on(changeset) == %{
               purge_start_disk_space: [
                 "Error in artifact cleanup values. The trigger value has to be specified when a goal is set"
               ]
             }
    end

    test "refuses a trigger above the goal" do
      assert {:error, changeset} =
               ServerConfig.update(%{
                 "purge_start_disk_space" => 60,
                 "purge_upto_disk_space" => 30
               })

      assert errors_on(changeset) == %{
               purge_start_disk_space: [
                 "Error in artifact cleanup values. The trigger value (60.0GB) should be less than the goal (30.0GB)"
               ]
             }
    end
  end

  # Sets exactly the named variables — a `nil` value removes one — and puts the
  # environment back afterwards.
  defp with_environment(variables, fun) do
    before = Map.new(variables, fn {variable, _} -> {variable, System.get_env(variable)} end)
    Enum.each(variables, fn {variable, value} -> set_env(variable, value) end)

    try do
      fun.()
    after
      Enum.each(before, fn {variable, value} -> set_env(variable, value) end)
    end
  end

  defp set_env(variable, nil), do: System.delete_env(variable)
  defp set_env(variable, value), do: System.put_env(variable, value)
end
