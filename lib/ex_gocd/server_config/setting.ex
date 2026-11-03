defmodule ExGoCD.ServerConfig.Setting do
  @moduledoc """
  The one row of this server's own settings.

  A null column means "not set here", never "the empty string": the environment
  supplies that value until an administrator stores one (see
  `ExGoCD.ServerConfig`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  # GoCD's own rules, from `com.thoughtworks.go.domain.SiteUrl`,
  # `SecureSiteUrl` and `com.thoughtworks.go.config.PurgeSettings`.
  @site_url_format ~r/^https?:\/\/.+/
  @secure_site_url_format ~r/^https:\/\/.+/

  @fields ~w(site_url secure_site_url default_job_timeout artifacts_dir
             purge_start_disk_space purge_upto_disk_space)a

  @primary_key {:id, :integer, autogenerate: false}
  schema "server_configs" do
    field :site_url, :string
    field :secure_site_url, :string
    field :default_job_timeout, :string
    field :artifacts_dir, :string
    field :purge_start_disk_space, :float
    field :purge_upto_disk_space, :float

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Casts the settings being written. A field the attrs do not carry is left as it
  is, so each documented endpoint writes its own section and nothing else.

  `empty_values: []` keeps a blank value as a change: the rules below have to
  see it to refuse it, or to hand a blank site URL back to the environment.
  """
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields, empty_values: [])
    |> hand_blank_urls_back()
    |> validate_change(:site_url, &validate_site_url/2)
    |> validate_change(:secure_site_url, &validate_secure_site_url/2)
    |> validate_change(:default_job_timeout, &validate_job_timeout/2)
    |> validate_change(:artifacts_dir, &validate_artifacts_dir/2)
    |> validate_purge_settings()
  end

  # A blank URL is not a URL this server would send out: storing null is what
  # hands the setting back to the environment.
  defp hand_blank_urls_back(changeset) do
    Enum.reduce([:site_url, :secure_site_url], changeset, fn field, acc ->
      case get_change(acc, field) do
        blank when is_binary(blank) ->
          if String.trim(blank) == "", do: put_change(acc, field, nil), else: acc

        _absent ->
          acc
      end
    end)
  end

  defp validate_site_url(field, value) do
    if Regex.match?(@site_url_format, value) do
      []
    else
      [{field, "Invalid format for site url. '#{value}' must start with http/s"}]
    end
  end

  defp validate_secure_site_url(field, value) do
    if Regex.match?(@secure_site_url_format, value) do
      []
    else
      [{field, "Invalid format for secure site url. '#{value}' must start with https"}]
    end
  end

  defp validate_job_timeout(field, value) do
    case Float.parse(value) do
      {minutes, _rest} when minutes < 0 ->
        [{field, "Timeout cannot be a negative number as it represents number of minutes"}]

      :error ->
        [{field, "Timeout should be a valid number as it represents number of minutes"}]

      {_minutes, _rest} ->
        []
    end
  end

  defp validate_artifacts_dir(field, value) do
    cond do
      String.trim(value) == "" ->
        [{field, "Please provide a not empty value for artifactsdir"}]

      Path.expand(value) == File.cwd!() ->
        [{field, "artifactsdir should not point to the root of sand box [#{Path.expand(value)}]"}]

      true ->
        []
    end
  end

  # A goal without a trigger is ambiguous and a trigger above the goal never
  # stops purging; both are refused, in GoCD's words.
  defp validate_purge_settings(changeset) do
    trigger = get_field(changeset, :purge_start_disk_space)
    goal = get_field(changeset, :purge_upto_disk_space)

    cond do
      is_nil(trigger) and is_nil(goal) ->
        changeset

      is_nil(goal) ->
        add_error(
          changeset,
          :purge_upto_disk_space,
          "Error in artifact cleanup values. Please specify goal value"
        )

      is_nil(trigger) or trigger == 0 ->
        add_error(
          changeset,
          :purge_start_disk_space,
          "Error in artifact cleanup values. The trigger value has to be specified when a goal is set"
        )

      trigger > goal ->
        add_error(
          changeset,
          :purge_start_disk_space,
          "Error in artifact cleanup values. The trigger value (#{trigger}GB) should be less than the goal (#{goal}GB)"
        )

      true ->
        changeset
    end
  end
end
