defmodule ExGoCD.NotificationsTest do
  use ExGoCD.DataCase
  alias ExGoCD.{Accounts, Notifications}

  setup do
    {:ok, user} =
      Accounts.create_user(%{username: "notify-#{System.unique_integer()}", display_name: "N"})

    %{user: user}
  end

  test "creates and lists notification filters", %{user: user} do
    assert [] = Notifications.list_filters(user.id)

    {:ok, filter} =
      Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "build-linux",
        stage_name: "test",
        event: "fails"
      })

    assert filter.event == "fails"

    assert [%{pipeline_name: "build-linux"}] = Notifications.list_filters(user.id)
  end

  test "deletes notification filters", %{user: user} do
    {:ok, filter} =
      Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "deploy",
        stage_name: "deploy",
        event: "breaks"
      })

    {:ok, _} = Notifications.delete_filter(filter.id)
    assert [] = Notifications.list_filters(user.id)
  end

  test "validates event type" do
    {:ok, user} =
      Accounts.create_user(%{username: "v-#{System.unique_integer()}", display_name: "V"})

    {:error, cs} =
      Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "x",
        stage_name: "y",
        event: "invalid"
      })

    assert "is invalid" in errors_on(cs).event
  end
end
