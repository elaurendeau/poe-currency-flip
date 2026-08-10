defmodule PoeFlipFinder.Gateways.EctoLeagueSyncGatewayTest do
  use PoeFlipFinder.DataCase, async: true

  alias PoeFlipFinder.Gateways.EctoLeagueSyncGateway
  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.League

  test "inserts a new league, marking it known to GGG" do
    league = %League{
      id: nil,
      external_id: "Allflame",
      display_name: "Allflame",
      is_current: true,
      has_exchange_activity: false
    }

    [result] = EctoLeagueSyncGateway.upsert_from_ggg([league])

    assert result.external_id == "Allflame"
    assert result.is_current == true
    persisted = Repo.get_by!(Schema.League, external_id: "Allflame")
    assert persisted.known_to_ggg == true
  end

  test "persists and round-trips start_at, per docs/PRD.md § 7.14's day-of-league need" do
    league = %League{
      id: nil,
      external_id: "Allflame",
      display_name: "Allflame",
      is_current: true,
      has_exchange_activity: false,
      start_at: ~U[2026-07-24 20:00:00Z]
    }

    [result] = EctoLeagueSyncGateway.upsert_from_ggg([league])

    assert result.start_at == ~U[2026-07-24 20:00:00Z]
    persisted = Repo.get_by!(Schema.League, external_id: "Allflame")
    assert persisted.start_at == ~U[2026-07-24 20:00:00Z]
  end

  test "updates display_name and is_current on an existing league without touching has_exchange_activity" do
    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: "Allflame",
      display_name: "Old Name",
      is_current: false,
      has_exchange_activity: true,
      known_to_ggg: false
    )
    |> Repo.insert!()

    league = %League{
      id: nil,
      external_id: "Allflame",
      display_name: "Allflame",
      is_current: true,
      has_exchange_activity: false
    }

    [result] = EctoLeagueSyncGateway.upsert_from_ggg([league])

    assert result.display_name == "Allflame"
    assert result.is_current == true
    # Untouched -- only ingestion determines this, not a Leagues API sync.
    assert result.has_exchange_activity == true
  end
end
