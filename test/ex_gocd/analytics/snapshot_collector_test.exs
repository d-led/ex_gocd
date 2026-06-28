defmodule ExGoCD.Analytics.SnapshotCollectorTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Analytics.AgentSnapshot
  alias ExGoCD.{Analytics, Repo}

  describe "AgentSnapshot schema" do
    test "inserts a snapshot row with required fields" do
      snap =
        %AgentSnapshot{}
        |> AgentSnapshot.changeset(%{
          total: 5,
          idle: 3,
          building: 2,
          disabled: 0,
          lost_contact: 0,
          elastic: 0
        })
        |> Repo.insert!()

      assert snap.total == 5
      assert snap.idle == 3
      assert snap.building == 2
      assert snap.disabled == 0
      assert snap.lost_contact == 0
      assert snap.elastic == 0
      assert snap.inserted_at
    end

    test "requires total, idle, building" do
      changeset = AgentSnapshot.changeset(%AgentSnapshot{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).total
      assert "can't be blank" in errors_on(changeset).idle
      assert "can't be blank" in errors_on(changeset).building
    end
  end

  describe "analytics queries" do
    test "agent_snapshot_trends/1 returns recent rows" do
      AgentSnapshot.changeset(%AgentSnapshot{}, %{
        total: 3,
        idle: 2,
        building: 1,
        disabled: 0,
        lost_contact: 0,
        elastic: 0
      })
      |> Repo.insert!()

      AgentSnapshot.changeset(%AgentSnapshot{}, %{
        total: 5,
        idle: 3,
        building: 2,
        disabled: 0,
        lost_contact: 0,
        elastic: 0
      })
      |> Repo.insert!()

      trends = Analytics.agent_snapshot_trends(24)
      # Both rows are within the 24-hour window
      assert length(trends) >= 2
      assert hd(trends).total > 0
    end

    test "latest_agent_snapshot/0 returns most recent" do
      AgentSnapshot.changeset(%AgentSnapshot{}, %{
        total: 1,
        idle: 1,
        building: 0,
        disabled: 0,
        lost_contact: 0,
        elastic: 0
      })
      |> Repo.insert!()

      # Small delay so inserted_at differs
      Process.sleep(100)

      AgentSnapshot.changeset(%AgentSnapshot{}, %{
        total: 7,
        idle: 4,
        building: 3,
        disabled: 0,
        lost_contact: 0,
        elastic: 0
      })
      |> Repo.insert!()

      latest = Analytics.latest_agent_snapshot()
      assert latest.total == 7
      assert latest.idle == 4
    end
  end
end
