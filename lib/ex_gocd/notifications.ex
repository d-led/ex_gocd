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

  require Logger

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
    # Email delivery via Swoosh — when SMTP is configured.
    # For now, log the notification. The email template and SMTP config
    # are ready to be added when the operator configures mail server settings.
    Logger.info(
      "[Notifications] Would email user_id=#{filter.user_id}: " <>
        "#{pipeline_name}/#{stage_name} #{event} (#{result})"
    )

    # TODO: uncomment when Swoosh mailer is configured
    # ExGoCD.Mailer.stage_notification(filter.user_id, pipeline_name, stage_name, event, result)
    # |> ExGoCD.Mailer.deliver()
  end
end
