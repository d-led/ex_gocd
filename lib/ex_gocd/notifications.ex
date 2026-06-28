defmodule ExGoCD.Notifications do
  @moduledoc """
  Context for notification filters — which pipeline events users want emails for.

  GoCD parity: StageEvent and PipelineEvent notification routing.
  When a stage completes (Passes, Fails, Breaks, Fixed, Cancelled),
  matching filters trigger email delivery via Swoosh.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.Notifications.NotificationFilter

  @doc "Lists notification filters for a user."
  def list_filters(user_id),
    do: Repo.all(from f in NotificationFilter, where: f.user_id == ^user_id)

  @doc "Creates a notification filter."
  def create_filter(attrs \\ %{}) do
    %NotificationFilter{} |> NotificationFilter.changeset(attrs) |> Repo.insert()
  end

  @doc "Deletes a notification filter."
  def delete_filter(id), do: Repo.get!(NotificationFilter, id) |> Repo.delete()

  @doc """
  Dispatches notifications for a stage event.
  Finds all filters matching the pipeline + stage + event and sends emails.

  Events: "Passes", "Fails", "Breaks", "Fixed", "Cancelled", "All"
  """
  def dispatch(pipeline_name, stage_name, event, stage_result) do
    matched =
      Repo.all(
        from f in NotificationFilter,
          where:
            f.pipeline_name == ^pipeline_name and f.stage_name == ^stage_name and
              (f.event == ^event or f.event == "All")
      )

    Enum.each(matched, fn filter ->
      deliver(filter, pipeline_name, stage_name, event, stage_result)
    end)

    length(matched)
  end

  defp deliver(filter, pipeline_name, stage_name, event, result) do
    # Look up user email from notification filter's user association
    user = ExGoCD.Accounts.get_user!(filter.user_id)

    ExGoCD.Mailer.stage_notification(
      user.email,
      pipeline_name,
      stage_name,
      event,
      result
    )
  end
end
