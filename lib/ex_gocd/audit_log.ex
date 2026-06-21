defmodule ExGoCD.AuditLog do
  @moduledoc """
  Immutable audit log recording all administrative and pipeline actions.
  """
  use Ecto.Schema
  import Ecto.Query

  alias ExGoCD.Repo

  schema "audit_logs" do
    field :actor, :string
    field :action, :string
    field :resource_type, :string
    field :resource_name, :string
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Records an audit entry. Returns :ok (never raises — audit failures must not crash callers)."
  def log(actor, action, opts \\ []) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(%{
      actor: actor,
      action: action,
      resource_type: opts[:resource_type],
      resource_name: opts[:resource_name],
      details: opts[:details] || %{}
    }, [:actor, :action, :resource_type, :resource_name, :details])
    |> Repo.insert!()
    :ok
  rescue
    e ->
      IO.warn("AuditLog.log failed: #{inspect(e)}", [])
      :ok
  end

  @doc "Lists recent audit entries, newest first."
  def recent(limit \\ 50) do
    from(l in __MODULE__, order_by: [desc: l.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  @doc """
  Searches audit log entries with dynamic filters.

  All filters are optional and combine with AND logic.
  String fields use case-insensitive ILIKE.
  Date fields filter on `inserted_at`.
  Returns up to 200 entries, newest first.
  """
  def search(filters \\ %{}) do
    base_query()
    |> maybe_filter(:actor, filters[:actor])
    |> maybe_filter(:action, filters[:action])
    |> maybe_filter(:resource_type, filters[:resource_type])
    |> maybe_filter(:resource_name, filters[:resource_name])
    |> maybe_date_from(filters[:date_from])
    |> maybe_date_to(filters[:date_to])
    |> order_by(desc: :inserted_at)
    |> limit(200)
    |> Repo.all()
  end

  defp base_query, do: from(l in __MODULE__)

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, field, value) when is_binary(value) do
    pattern = "%#{value}%"
    from(l in query, where: ilike(field(l, ^field), ^pattern))
  end

  defp maybe_date_from(query, nil), do: query

  defp maybe_date_from(query, %Date{} = date) do
    naive = NaiveDateTime.new!(date, ~T[00:00:00])
    from(l in query, where: l.inserted_at >= ^naive)
  end

  defp maybe_date_to(query, nil), do: query

  defp maybe_date_to(query, %Date{} = date) do
    naive = date |> Date.add(1) |> then(&NaiveDateTime.new!(&1, ~T[00:00:00]))
    from(l in query, where: l.inserted_at < ^naive)
  end
end
