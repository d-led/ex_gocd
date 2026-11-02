defmodule ExGoCD.Notifications do
  @moduledoc """
  Context for notification filters — which pipeline events users want emails for.

  GoCD parity: StageEvent and PipelineEvent notification routing.
  When a stage completes, matching filters trigger email delivery via Swoosh.

  The events are the words a filter stores, lowercase: `"passes"`, `"fails"`,
  `"cancelled"`, and `"all"` for every event. `"breaks"` and `"fixed"` are
  accepted by a filter but nothing dispatches them yet — they need the previous
  result of the stage to tell a break from a plain failure.
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Notifications.NotificationFilter
  alias ExGoCD.Repo

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

  `event` is the word a filter stores: "passes", "fails", "cancelled". A filter
  set to "all" matches every event.
  """
  def dispatch(pipeline_name, stage_name, event, stage_result, opts \\ []) do
    matched =
      Repo.all(
        from f in NotificationFilter,
          where:
            f.pipeline_name == ^pipeline_name and f.stage_name == ^stage_name and
              (f.event == ^event or f.event == "all")
      )

    Enum.each(matched, fn filter ->
      deliver(filter, pipeline_name, stage_name, event, stage_result, opts)
    end)

    length(matched)
  end

  defp deliver(filter, pipeline_name, stage_name, event, result, opts) do
    user = ExGoCD.Accounts.get_user!(filter.user_id)

    # Use username as the email identifier (ex_gocd users identify by username).
    ExGoCD.Mailer.stage_notification(user.username,
      pipeline_name: pipeline_name,
      stage_name: stage_name,
      event: event,
      result: result,
      pipeline_counter: opts[:pipeline_counter],
      stage_counter: opts[:stage_counter],
      triggered_by: opts[:triggered_by],
      materials: opts[:materials] || []
    )
  end
end
