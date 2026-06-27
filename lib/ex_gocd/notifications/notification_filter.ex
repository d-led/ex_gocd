defmodule ExGoCD.Notifications.NotificationFilter do
  @derive {Jason.Encoder, only: [:id, :user_id, :pipeline_name, :stage_name, :event, :match_committer]}
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @valid_events ~w(breaks fixed fails passes all)

  schema "notification_filters" do
    field :pipeline_name, :string
    field :stage_name, :string
    field :event, :string, default: "fails"
    field :match_committer, :boolean, default: false
    belongs_to :user, ExGoCD.Accounts.User
    timestamps()
  end

  @required_fields ~w(user_id pipeline_name stage_name event)a
  @optional_fields ~w(match_committer)a

  def changeset(filter, attrs) do
    filter
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event, @valid_events)
    |> unique_constraint([:user_id, :pipeline_name, :stage_name, :event])
  end
end
