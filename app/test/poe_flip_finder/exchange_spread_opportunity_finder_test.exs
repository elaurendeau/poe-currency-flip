defmodule PoeFlipFinder.ExchangeSpreadOpportunityFinderTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{
    Currency,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    ExchangeSpreadOpportunityFinder,
    League
  }

  # Ported 1:1 from ComputeFlipOpportunitiesInteractorTest's Exchange Spread
  # cases -- already drilled and confirmed traceable to docs/PRD.md § 7.2
  # (see docs/ELIXIR_TEST_MANIFESTO.md § Use-Case Discovery).

  @league %League{
    id: 1,
    external_id: "Standard",
    display_name: "Standard",
    is_current: false,
    has_exchange_activity: true
  }
  @chaos %Currency{
    id: 1,
    external_id: "Metadata/Items/Currency/CurrencyRerollRare",
    display_name: "Chaos Orb",
    category: :currency
  }
  @wisdom %Currency{
    id: 2,
    external_id: "Metadata/Items/Currency/CurrencyIdentification",
    display_name: "Scroll of Wisdom",
    category: :currency
  }
  @divine %Currency{
    id: 3,
    external_id: "Metadata/Items/Currency/CurrencyModValues",
    display_name: "Divine Orb",
    category: :currency
  }
  @portal %Currency{
    id: 4,
    external_id: "Metadata/Items/Currency/CurrencyPortal",
    display_name: "Portal Scroll",
    category: :currency
  }

  @rate_210 %DivineChaosRate{
    chaos_currency: @chaos,
    divine_currency: @divine,
    chaos_per_divine: 210.0
  }

  defp snapshot(
         currency_a,
         currency_b,
         lowest_ratio_a,
         lowest_ratio_b,
         highest_ratio_a,
         highest_ratio_b,
         stocks \\ {50, 60, 50, 60}
       ) do
    {lowest_stock_a, highest_stock_a, lowest_stock_b, highest_stock_b} = stocks

    %ExchangeMarketSnapshot{
      id: 1,
      generation_id: 999,
      league: @league,
      currency_a: currency_a,
      currency_b: currency_b,
      snapshot_hour: DateTime.utc_now(),
      volume_traded_a: 100,
      volume_traded_b: 100,
      lowest_stock_a: lowest_stock_a,
      highest_stock_a: highest_stock_a,
      lowest_stock_b: lowest_stock_b,
      highest_stock_b: highest_stock_b,
      lowest_ratio_a: lowest_ratio_a,
      highest_ratio_a: highest_ratio_a,
      lowest_ratio_b: lowest_ratio_b,
      highest_ratio_b: highest_ratio_b
    }
  end

  test "chaos/wisdom pair undercuts both legs before computing profit" do
    # Raw observed extremes are 185:1 and 366:1 (Chaos:Wisdom). Per
    # docs/PRD.md § 7.2, the buy leg floors then undercuts by -1
    # (366 -> 365) and the sell leg floors then undercuts by +1
    # (185 -> 186) -- these are the actually-postable prices, not the raw
    # historical extremes.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find([snapshot(@chaos, @wisdom, 1, 185, 1, 366)], @rate_210)

    assert opportunity.technique == :exchange_spread
    assert hd(opportunity.start).currency == @chaos
    assert hd(opportunity.start).quantity == 1.0
    assert hd(opportunity.via).currency == @wisdom
    assert_in_delta hd(opportunity.via).quantity, 365.0, 0.001
    assert hd(opportunity.sell).currency == @chaos
    assert_in_delta hd(opportunity.sell).quantity, 1.962366, 0.001
    assert_in_delta opportunity.margin_percent, 96.2366, 0.01
    assert opportunity.profit.currency == @chaos
    assert_in_delta opportunity.profit.quantity, 0.962366, 0.001
    # highest_stock_a -- the buy-leg extreme won here.
    assert opportunity.volume == 60
    assert opportunity.detail == "buy 365:1 · sell 186:1"
  end

  test "chaos in slot B still undercuts correctly after anchor swap" do
    # Same real-world rates as above, just recorded with chaos as
    # currency_b instead of a -- GGG's own pair ordering isn't something we
    # control, so the finder must anchor and undercut correctly regardless
    # of which slot the base currency is in.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@wisdom, @chaos, 185, 1, 366, 1, {10, 20, 50, 60})],
        @rate_210
      )

    assert hd(opportunity.start).currency == @chaos
    assert_in_delta hd(opportunity.via).quantity, 365.0, 0.001
    assert_in_delta hd(opportunity.sell).quantity, 1.962366, 0.001
    assert_in_delta opportunity.profit.quantity, 0.962366, 0.001
    # Chaos is currency_b here, so the buy-leg stock must come from the B
    # side (60), not A's (20) -- proves volume followed the anchor swap too.
    assert opportunity.volume == 60
  end

  test "neither currency is chaos or divine: filtered out" do
    # docs/PRD.md § 7.2: Exchange Spread must always start/sell in Chaos or
    # Divine -- an arbitrary altcoin-to-altcoin pair isn't a flip a player
    # can meaningfully act on without already holding that specific altcoin.
    assert ExchangeSpreadOpportunityFinder.find(
             [snapshot(@wisdom, @portal, 1, 4, 1, 4)],
             @rate_210
           ) == []
  end

  test "buy side cannot sustain the undercut: dropped" do
    # Reference buy rate floors to 1, so undercutting by -1 would go to 0 --
    # there's no way to post a meaningful buy order here (buying Divine
    # Orb with a single Chaos Orb: the raw rate is well under 1).
    assert ExchangeSpreadOpportunityFinder.find(
             [snapshot(@chaos, @wisdom, 2, 2, 2, 3)],
             @rate_210
           ) == []
  end

  test "chaos and divine pair itself is dropped since one chaos cannot buy a whole divine" do
    # A real Chaos<->Divine rate (~210 chaos per divine) means "buying
    # Divine with 1 Chaos" nets a small fraction of a Divine, which can't
    # sustain the -1 undercut -- this pair's own listing is correctly
    # dropped even though Chaos still wins the anchor slot.
    assert ExchangeSpreadOpportunityFinder.find(
             [snapshot(@divine, @chaos, 1, 200, 1, 210)],
             @rate_210
           ) == []
  end

  test "chaos and divine both qualify: chaos still wins the anchor slot" do
    # Deliberately unrealistic ratios (not a real Chaos/Divine rate) -- this
    # isolates the anchor-preference rule (Chaos beats Divine when both are
    # present) from the undercut-viability question covered above.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find([snapshot(@divine, @chaos, 1, 1, 3, 1)], @rate_210)

    assert hd(opportunity.start).currency == @chaos
    assert hd(opportunity.via).currency == @divine
    assert opportunity.profit.currency == @chaos
  end

  test "divine-anchored pair converts profit to chaos using the chaos/divine rate" do
    # Divine-anchored pair: identical raw shape to the Chaos/Wisdom worked
    # example, but starting from Divine instead of Chaos. The undercut math
    # is unit-agnostic (365 wisdom bought, 1.962366 *Divine* received
    # back), so the raw profit is 0.962366 Divine, which must become
    # 0.962366 * 210 = 202.0968 Chaos.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@divine, @wisdom, 1, 185, 1, 366)],
        @rate_210
      )

    assert hd(opportunity.start).currency == @divine
    # Unit-agnostic, unaffected by conversion.
    assert_in_delta opportunity.margin_percent, 96.2366, 0.01
    assert opportunity.profit.currency == @chaos
    assert_in_delta opportunity.profit.quantity, 202.0968, 0.01
  end

  test "divine-anchored pair with no chaos/divine rate available is skipped" do
    # No Chaos<->Divine snapshot anywhere in the active generation --
    # profit can't be safely normalized to Chaos, so the pair is dropped
    # rather than shown with a misleading unit.
    assert ExchangeSpreadOpportunityFinder.find([snapshot(@divine, @wisdom, 1, 185, 1, 366)], nil) ==
             []
  end

  test "multiple pairs produce one opportunity per pair, no reverse direction" do
    snapshots = [
      snapshot(@chaos, @wisdom, 1, 185, 1, 366),
      snapshot(@chaos, @portal, 1, 36, 1, 140)
    ]

    opportunities = ExchangeSpreadOpportunityFinder.find(snapshots, @rate_210)

    assert length(opportunities) == 2

    assert Enum.map(opportunities, &hd(&1.via).currency) |> Enum.sort() ==
             Enum.sort([@wisdom, @portal])
  end

  test "tied extremes: undercutting both legs nets a small loss" do
    # With no real spread (both extremes identical), undercutting the buy
    # leg down and the sell leg up costs a little on each side -- a small
    # guaranteed loss, not exactly zero. This is the realistic cost of
    # actually getting both legs filled.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find([snapshot(@chaos, @wisdom, 1, 185, 1, 185)], @rate_210)

    assert_in_delta opportunity.margin_percent, -1.0753, 0.01
    assert_in_delta opportunity.profit.quantity, -0.010753, 0.0001
  end

  test "non-finite extreme skips that snapshot rather than erroring" do
    # lowest_ratio_a=0 makes price_at_lowest = ratio_b/0 -- must not
    # surface an Infinity/NaN row to the frontend, and must not crash.
    assert ExchangeSpreadOpportunityFinder.find(
             [snapshot(@chaos, @wisdom, 0, 185, 1, 366)],
             @rate_210
           ) == []
  end

  test "zero volume exchange spread is excluded" do
    # Same chaos-wisdom pair as the undercut test above, but with the buy
    # leg's stock (highest_stock_a, since 366 is the higher extreme)
    # driven to 0 -- the finder itself doesn't drop zero-volume rows (that
    # filter is applied once at merge time in the context, per
    # docs/PRD.md § 7.2/7.5), so this asserts the *volume field* correctly
    # reports 0 for the caller to filter on.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@chaos, @wisdom, 1, 185, 1, 366, {50, 0, 50, 60})],
        @rate_210
      )

    assert opportunity.volume == 0
  end
end
