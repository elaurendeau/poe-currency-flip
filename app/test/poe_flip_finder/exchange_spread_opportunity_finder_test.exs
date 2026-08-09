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
         stocks \\ {50, 60, 50, 60},
         volumes \\ {100, 100}
       ) do
    {lowest_stock_a, highest_stock_a, lowest_stock_b, highest_stock_b} = stocks
    {volume_traded_a, volume_traded_b} = volumes

    %ExchangeMarketSnapshot{
      id: 1,
      generation_id: 999,
      league: @league,
      currency_a: currency_a,
      currency_b: currency_b,
      snapshot_hour: DateTime.utc_now(),
      volume_traded_a: volume_traded_a,
      volume_traded_b: volume_traded_b,
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
    # (366 -> 365). The sell leg uses the hour's volume-weighted average
    # rate, not the raw 185 extreme directly -- volumes {1, 185} here make
    # that average land exactly on 185 (every trade this hour behaved as if
    # it happened at the low extreme), so it floors then undercuts by +1
    # the same way (185 -> 186), matching this worked example either way.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@chaos, @wisdom, 1, 185, 1, 366, {50, 60, 50, 60}, {1, 185})],
        @rate_210
      )

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
        [snapshot(@wisdom, @chaos, 185, 1, 366, 1, {10, 20, 50, 60}, {185, 1})],
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

  test "chaos and divine pair retries inverted when 1 chaos can't buy a whole divine" do
    # A real Chaos<->Divine rate (~210 chaos per divine) means "buying
    # Divine with 1 Chaos" nets a small fraction of a Divine, which can't
    # sustain the -1 undercut -- the direct orientation (anchored on
    # Chaos, quoting "Divine per 1 Chaos") isn't viable. Per docs/PRD.md
    # § 7.2, the finder retries anchored on the item instead (quoting
    # "Chaos per 1 Divine"): raw extremes 200/210 floor+undercut to a
    # postable 209 (buy) / 201 (sell), still Chaos-anchored on Start/Sell
    # like every other row, just priced per-Divine instead of per-Chaos.
    # Volumes {1, 200} (Divine, Chaos) make the volume-weighted sell
    # average land exactly on the 200 extreme, matching this worked
    # example's numbers unchanged.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@divine, @chaos, 1, 200, 1, 210, {50, 60, 50, 60}, {1, 200})],
        @rate_210
      )

    assert hd(opportunity.start).currency == @chaos
    assert hd(opportunity.start).quantity == 209.0
    assert hd(opportunity.via).currency == @divine
    assert hd(opportunity.via).quantity == 1.0
    assert hd(opportunity.sell).currency == @chaos
    assert hd(opportunity.sell).quantity == 201.0
    assert_in_delta opportunity.margin_percent, -3.8278, 0.01
    assert opportunity.profit.currency == @chaos
    assert_in_delta opportunity.profit.quantity, -8.0, 0.001
    assert opportunity.start_chaos_equivalent == 209.0
    assert opportunity.detail == "buy 209:1 · sell 201:1"
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
    # @wisdom here stands in for a hypothetical item worth 2-4 Divine (not
    # its real in-game value) -- since a Divine-anchored direct quote
    # buying more than 1 whole unit of the other currency is now dropped
    # (see the "bulk-scale" test below), a *profitable* Divine-anchored
    # example has to use the inverted orientation (buy exactly 1 unit of
    # an item worth more than 1 Divine), the same as § 7.2's Chaos/Divine
    # worked example, just one level up in value. Raw extremes 2:1/4:1
    # (Divine:item) invert to buy 1 item for 3 Divine (floor(4)-1) and
    # sell it back for 4 Divine (volume-weighted 3/1=3, floor+1=4) --
    # profit 1 Divine, which must become 1 * 210 = 210 Chaos.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@divine, @wisdom, 2, 1, 4, 1, {50, 60, 50, 60}, {3, 1})],
        @rate_210
      )

    assert hd(opportunity.start).currency == @divine
    assert_in_delta hd(opportunity.start).quantity, 3.0, 0.001
    assert_in_delta hd(opportunity.via).quantity, 1.0, 0.001
    assert_in_delta opportunity.margin_percent, 33.333, 0.01
    assert opportunity.profit.currency == @chaos
    assert_in_delta opportunity.profit.quantity, 210.0, 0.01
    # 3 Divine start, converted via the same 210 chaos/divine rate.
    assert_in_delta opportunity.start_chaos_equivalent, 630.0, 0.001
  end

  test "divine-anchored direct quote buying more than 1 unit is dropped as bulk-scale" do
    # Regression test for real user feedback: "1 Divine Orb -> 3199 Orb of
    # Fusing" reads as a bulk trade, not the single-order competitive
    # spread this feature is about, even though the rate and liquidity are
    # both real. A Chaos-anchored pair with the identical shape (many
    # cheap units per 1 base unit) is exempt -- that's this feature's
    # normal, expected shape, not bulk (see the chaos/wisdom worked
    # example above, which buys 365 units per 1 Chaos and is kept).
    assert ExchangeSpreadOpportunityFinder.find(
             [snapshot(@divine, @wisdom, 1, 185, 1, 366, {50, 60, 50, 60}, {1, 185})],
             @rate_210
           ) == []
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
      ExchangeSpreadOpportunityFinder.find(
        [snapshot(@chaos, @wisdom, 1, 185, 1, 185, {50, 60, 50, 60}, {1, 185})],
        @rate_210
      )

    assert_in_delta opportunity.margin_percent, -1.0753, 0.01
    assert_in_delta opportunity.profit.quantity, -0.010753, 0.0001
  end

  test "wide-spread outlier fill no longer inflates margin into fantasy territory" do
    # Regression test for the real production bug reported by the user,
    # verified against live GGG data 2026-08-08 (Allflame league, Jeweller's
    # Orb vs Chaos Orb): raw lowest_ratio 1:75, highest_ratio 1:1. That 1:1
    # extreme is a single thin outlier fill (real in-game competitive rate
    # that hour was ~53-66:1), but the old "other extreme" sell logic
    # floored suggested_sell_price to 2, manufacturing a ~3600% fake margin
    # that would dominate any margin-sorted view of the opportunities list.
    # volume_traded {chaos: 3904, jeweller: 247240} is the real hourly total
    # -- its weighted average (~63.34) lands right where the real market
    # was, keeping the margin realistic instead of fantastical.
    [opportunity] =
      ExchangeSpreadOpportunityFinder.find(
        [
          snapshot(
            @chaos,
            @wisdom,
            1,
            75,
            1,
            1,
            {16_832, 17_970, 49_119, 93_210},
            {3904, 247_240}
          )
        ],
        @rate_210
      )

    assert opportunity.detail == "buy 74:1 · sell 64:1"
    assert opportunity.margin_percent < 50
    refute opportunity.detail == "buy 74:1 · sell 2:1"
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
