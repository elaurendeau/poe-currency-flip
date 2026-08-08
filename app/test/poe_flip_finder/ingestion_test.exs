defmodule PoeFlipFinder.IngestionTest do
  use PoeFlipFinder.DataCase, async: false

  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.Ingestion

  test "get_ingestion_freshness/0 reflects a fresh, never-refreshed state" do
    freshness = Ingestion.get_ingestion_freshness()

    assert freshness.last_processed_change_id == nil
    assert freshness.active_generation_refreshed_at == nil
  end

  test "get_ingestion_freshness/0 reflects a completed refresh's checkpoint and timestamp" do
    refreshed_at = DateTime.utc_now()

    Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(
      last_processed_change_id: 12_345,
      active_generation_refreshed_at: refreshed_at,
      updated_at: refreshed_at
    )
    |> Repo.update!()

    freshness = Ingestion.get_ingestion_freshness()

    assert freshness.last_processed_change_id == 12_345
    assert freshness.active_generation_refreshed_at == refreshed_at
  end
end
