defmodule ExGoCD.Notifications do
  @moduledoc "Context for notification filters — which pipeline events users want emails for."
  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.Notifications.NotificationFilter

  def list_filters(user_id),
    do: Repo.all(from f in NotificationFilter, where: f.user_id == ^user_id)

  def create_filter(attrs \\ %{}) do
    %NotificationFilter{} |> NotificationFilter.changeset(attrs) |> Repo.insert()
  end

  def delete_filter(id), do: Repo.get!(NotificationFilter, id) |> Repo.delete()
end
