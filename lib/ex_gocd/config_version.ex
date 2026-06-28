defmodule ExGoCD.ConfigVersion do
  @moduledoc """
  Immutable versioned snapshot of the full server configuration.

  Every time a config mutation occurs (pipeline, template, environment,
  elastic profile, k8s cluster, security, artifact store, etc.), the
  current full config is serialised and stored here.  This enables:

  - Browsing config history at /admin/config_xml
  - Diffing any two versions
  - Reverting to a previous version (re-import the stored config)

  GoCD parity: mirrors cruise-config.xml versioning, with the addition
  that encrypted secrets stay encrypted — we store `encryptedValue`
  (AES:iv:ciphertext) instead of plaintext.
  """

  use Ecto.Schema

  alias ExGoCD.Repo

  @type t :: %__MODULE__{
          id: pos_integer(),
          config_hash: String.t(),
          config_json: map(),
          config_xml: String.t() | nil,
          changed_by: String.t() | nil,
          change_reason: String.t() | nil,
          inserted_at: DateTime.t()
        }

  schema "config_versions" do
    field :config_hash, :string
    field :config_json, :map
    field :config_xml, :string
    field :changed_by, :string
    field :change_reason, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Returns recent versions, newest first."
  def recent(limit \\ 20) do
    import Ecto.Query

    from(v in __MODULE__,
      order_by: [desc: v.inserted_at],
      limit: ^limit,
      select: [:id, :config_hash, :changed_by, :change_reason, :inserted_at]
    )
    |> Repo.all()
  end

  @doc "Returns a specific version by id."
  def get!(id) do
    Repo.get!(__MODULE__, id)
  end

  @doc "Count of stored versions."
  def count do
    Repo.aggregate(__MODULE__, :count)
  end
end
