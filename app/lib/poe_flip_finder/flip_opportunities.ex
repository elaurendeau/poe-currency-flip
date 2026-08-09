defmodule PoeFlipFinder.FlipOpportunities do
  @moduledoc """
  Computes flip opportunities for a league, merging every implemented
  technique into one ranked list: Exchange Spread (docs/PRD.md § 7.2),
  Bulk Buy (§ 7.5), Divination Card (§ 7.3), and Vendor Recipe (§ 7.1).
  """

  alias PoeFlipFinder.{
    BulkBuyOpportunityFinder,
    DivinationCardOpportunityFinder,
    DivineChaosRate,
    ExchangeSpreadOpportunityFinder,
    FlipOpportunity,
    VendorRecipeOpportunityFinder
  }

  @spec compute_flip_opportunities(String.t()) :: [FlipOpportunity.t()]
  def compute_flip_opportunities(league_external_id) do
    snapshots = snapshot_query_gateway().find_active_snapshots(league_external_id)
    rate = DivineChaosRate.resolve(snapshots)
    card_rewards = divination_card_reference_gateway().find_all()
    vendor_recipes = vendor_recipe_reference_gateway().find_all()

    exchange_spread = ExchangeSpreadOpportunityFinder.find(snapshots, rate)
    bulk_buy = BulkBuyOpportunityFinder.find(snapshots, rate)
    divination_card = DivinationCardOpportunityFinder.find(snapshots, card_rewards, rate)
    vendor_recipe = VendorRecipeOpportunityFinder.find(snapshots, vendor_recipes, rate)

    # A leg with zero real stock behind it produced the ratio purely from
    # stale/outlier data (docs/PRD.md § 7.2/§ 7.5) -- no real opportunity
    # regardless of how attractive its margin looks. Applied once here,
    # across every technique, not per-finder.
    Enum.filter(
      exchange_spread ++ bulk_buy ++ divination_card ++ vendor_recipe,
      &(&1.volume > 0)
    )
  end

  defp snapshot_query_gateway do
    Application.get_env(
      :poe_flip_finder,
      :snapshot_query_gateway,
      PoeFlipFinder.Gateways.EctoSnapshotQueryGateway
    )
  end

  defp divination_card_reference_gateway do
    Application.get_env(
      :poe_flip_finder,
      :divination_card_reference_gateway,
      PoeFlipFinder.Gateways.BundledDivinationCardReferenceGateway
    )
  end

  defp vendor_recipe_reference_gateway do
    Application.get_env(
      :poe_flip_finder,
      :vendor_recipe_reference_gateway,
      PoeFlipFinder.Gateways.BundledVendorRecipeReferenceGateway
    )
  end
end
