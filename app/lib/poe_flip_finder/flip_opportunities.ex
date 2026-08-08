defmodule PoeFlipFinder.FlipOpportunities do
  @moduledoc """
  Computes flip opportunities for a league, merging every implemented
  technique into one ranked list. Currently Exchange Spread (docs/PRD.md
  § 7.2) and Bulk Buy (§ 7.5) -- Vendor Recipe and Divination Card have no
  reference data or computation logic in the Java codebase either (see the
  Phase 3 commit), so they contribute nothing here yet, matching current
  production behavior rather than inventing new scope.
  """

  alias PoeFlipFinder.{
    BulkBuyOpportunityFinder,
    DivineChaosRate,
    ExchangeSpreadOpportunityFinder,
    FlipOpportunity
  }

  @spec compute_flip_opportunities(String.t()) :: [FlipOpportunity.t()]
  def compute_flip_opportunities(league_external_id) do
    snapshots = snapshot_query_gateway().find_active_snapshots(league_external_id)
    rate = DivineChaosRate.resolve(snapshots)

    exchange_spread = ExchangeSpreadOpportunityFinder.find(snapshots, rate)
    bulk_buy = BulkBuyOpportunityFinder.find(snapshots, rate)

    # A leg with zero real stock behind it produced the ratio purely from
    # stale/outlier data (docs/PRD.md § 7.2/§ 7.5) -- no real opportunity
    # regardless of how attractive its margin looks. Applied once here,
    # across every technique, not per-finder.
    Enum.filter(exchange_spread ++ bulk_buy, &(&1.volume > 0))
  end

  defp snapshot_query_gateway do
    Application.get_env(
      :poe_flip_finder,
      :snapshot_query_gateway,
      PoeFlipFinder.Gateways.EctoSnapshotQueryGateway
    )
  end
end
