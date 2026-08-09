defmodule PoeFlipFinder.BulkBuyOpportunityFinderTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{
    BulkBuyOpportunityFinder,
    Currency,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    League
  }

  # Ported 1:1 from the Java BulkBuyOpportunityFinderTest -- these use cases
  # are already drilled and confirmed traceable to docs/PRD.md § 7.2/7.5
  # (see docs/ELIXIR_TEST_MANIFESTO.md § Use-Case Discovery): buy-competitive
  # / sell-market split, reference trade scaling, zero-volume/non-finite
  # guards, and the base-pair exclusion are all already documented there.

  @now ~U[2026-08-06 12:00:00Z]

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
  @divine %Currency{
    id: 2,
    external_id: "Metadata/Items/Currency/CurrencyModValues",
    display_name: "Divine Orb",
    category: :currency
  }
  @deck %Currency{
    id: 3,
    external_id: "Metadata/Items/DivinationCards/DivinationCardStackedDeck",
    display_name: "Stacked Deck",
    category: :cards
  }
  @wisdom %Currency{
    id: 4,
    external_id: "Metadata/Items/Currency/CurrencyIdentification",
    display_name: "Scroll of Wisdom",
    category: :currency
  }

  @rate_210 %DivineChaosRate{
    chaos_currency: @chaos,
    divine_currency: @divine,
    chaos_per_divine: 210.0
  }

  defp snapshot(currency_a, currency_b, ratios, stocks) do
    {lowest_ratio_a, lowest_ratio_b, highest_ratio_a, highest_ratio_b} = ratios
    {lowest_stock_a, highest_stock_a, lowest_stock_b, highest_stock_b} = stocks

    %ExchangeMarketSnapshot{
      id: 1,
      generation_id: 999,
      league: @league,
      currency_a: currency_a,
      currency_b: currency_b,
      snapshot_hour: @now,
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

  test "divine-to-chaos opportunity computed with hand-verified numbers" do
    # Chaos-deck leg: price_at_lowest=8, price_at_highest=13 -> buy=floor(13)-1=12,
    # market_sell_price = floor(13) = 13 -- the SAME extreme as the buy price
    # (the worse-for-a-seller one), not the round-trip-favorable 8. This is
    # the exact shape of a real production bug: a wide in-hour spread (here
    # 8 vs 13) previously fed the optimistic 8 into a one-directional sell,
    # overstating how much a real seller could get.
    chaos_leg = snapshot(@chaos, @deck, {1, 8, 1, 13}, {100, 50, 1, 1})

    # Divine-deck leg: price_at_lowest=1700, price_at_highest=1900 -> buy=1899.
    divine_leg = snapshot(@divine, @deck, {1, 1700, 1, 1900}, {30, 80, 1, 1})

    [opportunity] = BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210)

    assert opportunity.technique == :bulk_buy
    # Sells through the chaos leg's market price (13, not the
    # round-trip-favorable 8), so 1899 deck / 13 = 146.077 Chaos -- below
    # the 210 c/div direct baseline, i.e. this specific pair is a real loss
    # here, not a profitable flip -- the math still has to be reported
    # accurately either way.
    assert hd(opportunity.start).currency == @divine
    assert hd(opportunity.start).quantity == 1.0
    assert hd(opportunity.via).currency == @deck
    assert hd(opportunity.via).quantity == 1899.0
    assert hd(opportunity.sell).currency == @chaos
    assert_in_delta hd(opportunity.sell).quantity, 1899.0 / 13, 1.0e-7
    assert_in_delta opportunity.margin_percent, (1899.0 / 13 - 210) / 210 * 100, 0.001
    assert opportunity.profit.currency == @chaos
    assert_in_delta opportunity.profit.quantity, 1899.0 / 13 - 210, 1.0e-7
    # min(divine buy_leg_stock=80, chaos buy_leg_stock=50)
    assert opportunity.volume == 50
  end

  test "chaos leg's buy price collapses but its market sell price is still usable" do
    # Chaos-wisdom leg: price_at_lowest=1, price_at_highest=1.5 -> buy
    # floors to 0 (suggested_buy_price=nil), but market_sell_price=floor(1.5)=1
    # is still a valid, nonzero sell reference -- divine_to_chaos only
    # depends on the chaos leg's market_sell_price, not its (irrelevant,
    # collapsed) suggested_buy_price, so the opportunity must still compute.
    chaos_leg = snapshot(@chaos, @wisdom, {2, 2, 2, 3}, {40, 70, 1, 1})
    divine_leg = snapshot(@divine, @wisdom, {1, 50, 1, 80}, {30, 80, 1, 1})

    [opportunity] = BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210)

    assert hd(opportunity.start).currency == @divine
    assert hd(opportunity.sell).currency == @chaos
    # floor(80)-1
    assert hd(opportunity.via).quantity == 79.0
    # Sells through the chaos leg's market price (1, the floored raw
    # extreme with no +1 push), not the competitive 2 -- 79/1 = 79.
    assert_in_delta hd(opportunity.sell).quantity, 79.0, 1.0e-7
  end

  test "chaos leg price collapses below one: dropped safely, no crash" do
    # A real production incident: market_sell_price (no +1 push, unlike
    # suggested_sell_price) can floor to exactly 0 when its raw extreme is
    # below 1 -- e.g. both price_at_lowest=0.5 and price_at_highest=0.3
    # here. divine_to_chaos divides by chaos_leg.market_sell_price, so an
    # unguarded 0 would produce a crash rather than an empty result.
    chaos_leg = snapshot(@chaos, @wisdom, {2, 1, 10, 3}, {100, 50, 1, 1})
    divine_leg = snapshot(@divine, @wisdom, {1, 1700, 1, 1900}, {30, 80, 1, 1})

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210) == []
  end

  test "divine leg price collapses below one: dropped safely, no crash" do
    # divine_to_chaos uses divine_leg.suggested_buy_price as its via
    # amount -- when that collapses to nil (raw extreme below 1), the
    # opportunity must be dropped, not crash.
    chaos_leg = snapshot(@chaos, @deck, {1, 8, 1, 13}, {100, 50, 1, 1})
    divine_leg = snapshot(@divine, @deck, {2, 1, 10, 3}, {100, 50, 1, 1})

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210) == []
  end

  test "rate unavailable returns empty regardless of snapshots" do
    chaos_leg = snapshot(@chaos, @deck, {1, 8, 1, 13}, {100, 50, 1, 1})
    divine_leg = snapshot(@divine, @deck, {1, 1700, 1, 1900}, {30, 80, 1, 1})

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], nil) == []
  end

  test "no matching divine leg for the same intermediary is not a candidate" do
    chaos_leg = snapshot(@chaos, @deck, {1, 8, 1, 13}, {100, 50, 1, 1})

    assert BulkBuyOpportunityFinder.find([chaos_leg], @rate_210) == []
  end

  test "only the chaos/divine reference pair itself excludes it as a candidate" do
    chaos_divine = snapshot(@chaos, @divine, {210, 1, 210, 1}, {50, 60, 50, 60})

    assert BulkBuyOpportunityFinder.find([chaos_divine], @rate_210) == []
  end

  test "non-finite ratio on one leg drops that intermediary entirely" do
    # lowest_ratio_a=0
    chaos_leg = snapshot(@chaos, @deck, {0, 8, 1, 13}, {100, 50, 1, 1})
    divine_leg = snapshot(@divine, @deck, {1, 1700, 1, 1900}, {30, 80, 1, 1})

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210) == []
  end
end
