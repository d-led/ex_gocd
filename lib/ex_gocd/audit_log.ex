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

  @doc "Records an audit entry. Returns :ok."
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
    _ -> :ok
  end

  @doc "Lists recent audit entries, newest first."
  def recent(limit \\ 50) do
    from(l in __MODULE__, order_by: [desc: l.inserted_at], limit: ^limit)
    |> Repo.all()
  end
end
