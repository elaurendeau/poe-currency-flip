defmodule PoeFlipFinder.Gateways.EctoSnapshotQueryGatewayTest do
  use PoeFlipFinder.DataCase, async: true

  alias PoeFlipFinder.Gateways.EctoSnapshotQueryGateway
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

  defp insert_snapshot!(attrs) do
    defaults = %{
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

    %Schema.ExchangeMarketSnapshot{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp activate_generation!(generation_id) do
    Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(active_generation_id: generation_id, updated_at: DateTime.utc_now())
    |> Repo.update!()
  end

  test "returns snapshots for the active generation, hydrated with league and currencies" do
    chaos = insert_currency!("Chaos")
    divine = insert_currency!("Divine")
    league = insert_league!("Standard")

    insert_snapshot!(%{
      generation_id: 42,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: divine.id,
      lowest_ratio_a: 1.0,
      highest_ratio_b: 210.0
    })

    activate_generation!(42)

    [snapshot] = EctoSnapshotQueryGateway.find_active_snapshots("Standard")

    assert snapshot.league.external_id == "Standard"
    assert snapshot.currency_a.external_id == "Chaos"
    assert snapshot.currency_b.external_id == "Divine"
    assert snapshot.highest_ratio_b == 210.0
  end

  test "excludes snapshots from a superseded generation" do
    chaos = insert_currency!("Chaos")
    divine = insert_currency!("Divine")
    league = insert_league!("Standard")

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: divine.id
    })

    insert_snapshot!(%{
      generation_id: 2,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: divine.id
    })

    activate_generation!(2)

    snapshots = EctoSnapshotQueryGateway.find_active_snapshots("Standard")

    assert length(snapshots) == 1
    assert hd(snapshots).generation_id == 2
  end

  test "returns empty for an unrecognized league" do
    assert EctoSnapshotQueryGateway.find_active_snapshots("NoSuchLeague") == []
  end

  test "returns empty when no generation has ever gone live yet" do
    insert_league!("Standard")

    # Migration seeds active_generation_id=0 -- untouched here.
    assert EctoSnapshotQueryGateway.find_active_snapshots("Standard") == []
  end
end
