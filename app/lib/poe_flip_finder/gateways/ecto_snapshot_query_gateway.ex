defmodule PoeFlipFinder.Gateways.EctoSnapshotQueryGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.SnapshotQueryGateway`.
  Plain FK id fields on `Schema.ExchangeMarketSnapshot` (no `belongs_to`
  associations) mean hydrating back to domain entities needs explicit
  batched currency lookups rather than a preload.
  """

  @behaviour PoeFlipFinder.SnapshotQueryGateway

  import Ecto.Query

  alias PoeFlipFinder.{Currency, ExchangeMarketSnapshot, League}
  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.Repo

  # V1's Ecto equivalent seeds active_generation_id=0 for "nothing has ever
  # gone live yet" -- same sentinel the write side uses.
  @no_generation_yet 0

  @impl true
  def find_active_snapshots(league_external_id) do
    case Repo.get_by(Schema.League, external_id: league_external_id) do
      nil -> []
      league_schema -> find_for_league(league_schema)
    end
  end

  defp find_for_league(league_schema) do
    case active_generation_id() do
      @no_generation_yet ->
        []

      generation_id ->
        rows =
          Repo.all(
            from s in Schema.ExchangeMarketSnapshot,
              where: s.generation_id == ^generation_id and s.league_id == ^league_schema.id
          )

        currencies_by_id = hydrate_currencies(rows)
        league = to_league(league_schema)
        Enum.map(rows, &to_entity(&1, league, currencies_by_id))
    end
  end

  defp active_generation_id do
    case Repo.get(Schema.ExchangeIngestionState, 1) do
      nil -> @no_generation_yet
      state -> state.active_generation_id
    end
  end

  defp hydrate_currencies(rows) do
    currency_ids = rows |> Enum.flat_map(&[&1.currency_a_id, &1.currency_b_id]) |> Enum.uniq()

    Schema.Currency
    |> where([c], c.id in ^currency_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp to_entity(row, league, currencies_by_id) do
    %ExchangeMarketSnapshot{
      id: row.id,
      generation_id: row.generation_id,
      league: league,
      currency_a: to_currency(currencies_by_id[row.currency_a_id]),
      currency_b: to_currency(currencies_by_id[row.currency_b_id]),
      snapshot_hour: row.snapshot_hour,
      volume_traded_a: row.volume_traded_a,
      volume_traded_b: row.volume_traded_b,
      lowest_stock_a: row.lowest_stock_a,
      highest_stock_a: row.highest_stock_a,
      lowest_stock_b: row.lowest_stock_b,
      highest_stock_b: row.highest_stock_b,
      lowest_ratio_a: row.lowest_ratio_a,
      highest_ratio_a: row.highest_ratio_a,
      lowest_ratio_b: row.lowest_ratio_b,
      highest_ratio_b: row.highest_ratio_b
    }
  end

  defp to_league(%Schema.League{} = schema) do
    %League{
      id: schema.id,
      external_id: schema.external_id,
      display_name: schema.display_name,
      is_current: schema.is_current,
      has_exchange_activity: schema.has_exchange_activity,
      start_at: schema.start_at
    }
  end

  defp to_currency(%Schema.Currency{} = schema) do
    %Currency{
      id: schema.id,
      external_id: schema.external_id,
      display_name: schema.display_name,
      icon_url: schema.icon_url,
      category: schema.category
    }
  end
end
