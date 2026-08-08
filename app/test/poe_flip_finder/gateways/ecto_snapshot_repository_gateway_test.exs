defmodule PoeFlipFinder.Gateways.EctoSnapshotRepositoryGatewayTest do
  # async: false -- several tests here UPDATE the singleton
  # exchange_ingestion_state row (id=1) via commit_generation. Postgres row
  # locks are real even for sandboxed transactions that will roll back, so
  # running these concurrently deadlocks them against each other.
  use PoeFlipFinder.DataCase, async: false

  alias PoeFlipFinder.{Currency, ExchangeMarketSnapshot, League}
  alias PoeFlipFinder.Gateways.EctoSnapshotRepositoryGateway
  alias PoeFlipFinder.Gateways.Schema

  defp insert_currency!(external_id) do
    %Schema.Currency{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: external_id,
      category: :currency
    )
    |> Repo.insert!()
  end

  defp insert_league!(external_id) do
    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: external_id,
      known_to_ggg: true
    )
    |> Repo.insert!()
  end

  defp domain_snapshot(generation_id, league_schema, currency_a_schema, currency_b_schema) do
    %ExchangeMarketSnapshot{
      id: nil,
      generation_id: generation_id,
      league: %League{
        id: league_schema.id,
        external_id: league_schema.external_id,
        display_name: league_schema.display_name,
        is_current: false,
        has_exchange_activity: false
      },
      currency_a: %Currency{
        id: currency_a_schema.id,
        external_id: currency_a_schema.external_id,
        display_name: currency_a_schema.display_name,
        category: :currency
      },
      currency_b: %Currency{
        id: currency_b_schema.id,
        external_id: currency_b_schema.external_id,
        display_name: currency_b_schema.display_name,
        category: :currency
      },
      # Second precision, matching what DateTime.from_unix!/1 (what
      # GggExchangeSourceGateway actually produces) always has -- see
      # the "save_snapshots accepts a second-precision snapshot_hour" test.
      snapshot_hour: DateTime.utc_now() |> DateTime.truncate(:second),
      volume_traded_a: 10,
      volume_traded_b: 10,
      lowest_stock_a: 1,
      highest_stock_a: 1,
      lowest_stock_b: 1,
      highest_stock_b: 1,
      lowest_ratio_a: 1.0,
      highest_ratio_a: 1.0,
      lowest_ratio_b: 1.0,
      highest_ratio_b: 1.0
    }
  end

  test "read_ingestion_state reflects the singleton row" do
    freshness = EctoSnapshotRepositoryGateway.read_ingestion_state()

    # Migration seeds a fresh row with no checkpoint yet.
    assert freshness.last_processed_change_id == nil
    assert freshness.active_generation_refreshed_at == nil
  end

  test "start_new_generation mints a positive integer tag" do
    generation_id = EctoSnapshotRepositoryGateway.start_new_generation()

    assert is_integer(generation_id)
    assert generation_id > 0
  end

  test "save_snapshots accepts a second-precision snapshot_hour, matching real GGG-sourced data" do
    # Regression test: GggExchangeSourceGateway builds snapshot_hour via
    # DateTime.from_unix!/1 on a GGG change-stream epoch second, which has
    # second (not microsecond) precision. Repo.insert_all -- unlike
    # Repo.insert with a changeset -- does no precision coercion, so a
    # :utc_datetime_usec column crashed on this exact value against real
    # production data; every other test here happens to use
    # DateTime.utc_now() (microsecond precision), which masked the bug.
    league = insert_league!("Standard")
    chaos = insert_currency!("Chaos")
    divine = insert_currency!("Divine")

    real_shaped_hour = DateTime.from_unix!(1_754_481_600)
    snapshot = %{domain_snapshot(1, league, chaos, divine) | snapshot_hour: real_shaped_hour}

    assert :ok = EctoSnapshotRepositoryGateway.save_snapshots([snapshot])

    [saved] = Repo.all(Schema.ExchangeMarketSnapshot)
    assert DateTime.compare(saved.snapshot_hour, real_shaped_hour) == :eq
  end

  test "commit_generation activates the new generation and purges the superseded one" do
    league = insert_league!("Standard")
    chaos = insert_currency!("Chaos")
    divine = insert_currency!("Divine")

    :ok =
      EctoSnapshotRepositoryGateway.save_snapshots([domain_snapshot(1, league, chaos, divine)])

    :ok = EctoSnapshotRepositoryGateway.commit_generation(1, 100)

    :ok =
      EctoSnapshotRepositoryGateway.save_snapshots([domain_snapshot(2, league, chaos, divine)])

    :ok = EctoSnapshotRepositoryGateway.commit_generation(2, 200)

    state = Repo.get!(Schema.ExchangeIngestionState, 1)
    assert state.active_generation_id == 2
    assert state.last_processed_change_id == 200
    assert state.active_generation_refreshed_at != nil

    remaining = Repo.all(Schema.ExchangeMarketSnapshot)
    assert Enum.map(remaining, & &1.generation_id) == [2]
  end

  test "commit_generation on the very first run does not attempt to purge generation zero" do
    league = insert_league!("Standard")
    chaos = insert_currency!("Chaos")
    divine = insert_currency!("Divine")

    :ok =
      EctoSnapshotRepositoryGateway.save_snapshots([domain_snapshot(1, league, chaos, divine)])

    # Migration seeds active_generation_id=0 ("no generation yet") -- this
    # must not crash trying to purge a nonexistent generation 0.
    assert :ok = EctoSnapshotRepositoryGateway.commit_generation(1, 100)

    assert length(Repo.all(Schema.ExchangeMarketSnapshot)) == 1
  end

  test "discard_generation purges rows without touching the active checkpoint" do
    league = insert_league!("Standard")
    chaos = insert_currency!("Chaos")
    divine = insert_currency!("Divine")

    :ok =
      EctoSnapshotRepositoryGateway.save_snapshots([domain_snapshot(1, league, chaos, divine)])

    :ok = EctoSnapshotRepositoryGateway.commit_generation(1, 100)

    :ok =
      EctoSnapshotRepositoryGateway.save_snapshots([domain_snapshot(99, league, chaos, divine)])

    :ok = EctoSnapshotRepositoryGateway.discard_generation(99)

    state = Repo.get!(Schema.ExchangeIngestionState, 1)
    # Untouched by the discard -- still pointing at generation 1.
    assert state.active_generation_id == 1

    remaining = Repo.all(Schema.ExchangeMarketSnapshot)
    assert Enum.map(remaining, & &1.generation_id) == [1]
  end
end
