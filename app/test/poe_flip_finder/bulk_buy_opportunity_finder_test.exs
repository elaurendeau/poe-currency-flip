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

  @league %League{id: 1, external_id: "Standard", display_name: "Standard", is_current: false, has_exchange_activity: true}
  @chaos %Currency{id: 1, external_id: "Metadata/Items/Currency/CurrencyRerollRare", display_name: "Chaos Orb", item_type: :currency}
  @divine %Currency{id: 2, external_id: "Metadata/Items/Currency/CurrencyModValues", display_name: "Divine Orb", item_type: :currency}
  @deck %Currency{
    id: 3,
    external_id: "Metadata/Items/DivinationCards/DivinationCardStackedDeck",
    display_name: "Stacked Deck",
    item_type: :divination_card
  }
  @wisdom %Currency{id: 4, external_id: "Metadata/Items/Currency/CurrencyIdentification", display_name: "Scroll of Wisdom", item_type: :currency}

  @rate_210 %DivineChaosRate{chaos_currency: @chaos, divine_currency: @divine, chaos_per_divine: 210.0}

  defp snapshot(
         currency_a,
         currency_b,
         lowest_ratio_a,
         lowest_ratio_b,
         highest_ratio_a,
         highest_ratio_b,
         lowest_stock_a,
         highest_stock_a,
         lowest_stock_b,
         highest_stock_b
       ) do
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

  test "both directions viable produces two opportunities with hand-verified numbers" do
    # Chaos-deck leg: price_at_lowest=8, price_at_highest=13 -> buy=floor(13)-1=12.
    # market_sell_price = floor(13) = 13 -- the SAME extreme as the buy price
    # (the worse-for-a-seller one), not the round-trip-favorable 8. This is
    # the exact shape of a real production bug: a wide in-hour spread (here
    # 8 vs 13) previously fed the optimistic 8 into a one-directional sell,
    # overstating how much a real seller could get.
    chaos_leg = snapshot(@chaos, @deck, 1, 8, 1, 13, 100, 50, 1, 1)
    # Divine-deck leg: price_at_lowest=1700, price_at_highest=1900 -> buy=1899, market_sell_price=floor(1900)=1900.
    divine_leg = snapshot(@divine, @deck, 1, 1700, 1, 1900, 30, 80, 1, 1)

    opportunities = BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210)

    assert length(opportunities) == 2
    chaos_to_divine = Enum.find(opportunities, &(hd(&1.sell).currency == @divine))
    divine_to_chaos = Enum.find(opportunities, &(hd(&1.sell).currency == @chaos))

    # Rescaled so the trade always ends at exactly 1 Divine sold instead of
    # starting from 1 Chaos ("1 Chaos -> 0.005 Divine" is a meaningless
    # fraction to read): via always equals the divine leg's *market* sell
    # price (1900, the worse-for-a-seller real hourly extreme -- same one
    # the buy price is undercut from, floored with no further push), and
    # start is however much Chaos that took (1900/12 = 158.333). Margin is
    # unaffected by the rescaling itself (still scale-invariant); profit
    # scales up proportionally.
    assert chaos_to_divine.technique == :bulk_buy
    assert hd(chaos_to_divine.start).currency == @chaos
    assert_in_delta hd(chaos_to_divine.start).quantity, 1900.0 / 12, 0.001
    assert hd(chaos_to_divine.via).currency == @deck
    assert hd(chaos_to_divine.via).quantity == 1900.0
    assert hd(chaos_to_divine.sell).quantity == 1.0
    assert_in_delta chaos_to_divine.margin_percent, 31.0 / 95 * 100, 0.001
    assert chaos_to_divine.profit.currency == @chaos
    assert_in_delta chaos_to_divine.profit.quantity, 155.0 / 3, 0.001
    # min(chaos buy_leg_stock=50, divine buy_leg_stock=80)
    assert chaos_to_divine.volume == 50

    # Divine->Chaos sells through the chaos leg's market price (13, not the
    # round-trip-favorable 8), so 1899 deck / 13 = 146.077 Chaos -- below
    # the 210 c/div direct baseline, i.e. this direction is a real loss
    # even though the reverse direction is profitable. Exactly the
    # asymmetry BulkBuyOpportunityFinder's moduledoc calls out: each
    # direction is evaluated independently, and one being viable says
    # nothing about the other.
    assert hd(divine_to_chaos.start).currency == @divine
    assert hd(divine_to_chaos.start).quantity == 1.0
    assert hd(divine_to_chaos.via).quantity == 1899.0
    assert_in_delta hd(divine_to_chaos.sell).quantity, 1899.0 / 13, 1.0e-7
    assert_in_delta divine_to_chaos.margin_percent, (1899.0 / 13 - 210) / 210 * 100, 0.001
    assert divine_to_chaos.profit.currency == @chaos
    assert_in_delta divine_to_chaos.profit.quantity, 1899.0 / 13 - 210, 1.0e-7
    # min(divine buy_leg_stock=80, chaos buy_leg_stock=50)
    assert divine_to_chaos.volume == 50
  end

  test "chaos buy leg not viable, only divine-to-chaos direction survives" do
    # Chaos-wisdom leg: price_at_lowest=1, price_at_highest=1.5 -> buy floors
    # to 0 (invalid), but sell=floor(1)+1=2 is still valid -- this is
    # exactly the asymmetry UndercutQuote exists to expose: a naive "drop
    # both legs if either quote is unusable" would incorrectly return 0
    # opportunities here.
    chaos_leg = snapshot(@chaos, @wisdom, 2, 2, 2, 3, 40, 70, 1, 1)
    divine_leg = snapshot(@divine, @wisdom, 1, 50, 1, 80, 30, 80, 1, 1)

    opportunities = BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210)

    assert length(opportunities) == 1
    [opportunity] = opportunities
    assert hd(opportunity.start).currency == @divine
    assert hd(opportunity.sell).currency == @chaos
    # floor(80)-1
    assert hd(opportunity.via).quantity == 79.0
    # Sells through the chaos leg's market price (1, the floored raw
    # extreme with no +1 push), not the competitive 2 -- 79/1 = 79.
    assert_in_delta hd(opportunity.sell).quantity, 79.0, 1.0e-7
  end

  test "chaos leg price collapses below one: both directions dropped safely, no crash" do
    # A real production incident: market_sell_price (no +1 push, unlike
    # suggested_sell_price) can floor to exactly 0 when its raw extreme is
    # below 1 -- e.g. both price_at_lowest=0.5 and price_at_highest=0.3
    # here. divine_to_chaos divides by chaos_leg.market_sell_price, so an
    # unguarded 0 would produce a crash rather than an empty result.
    #
    # market_sell_price shares its raw extreme with suggested_buy_price
    # (see UndercutQuote), so a leg's price collapsing below 1 always takes
    # out BOTH directions that leg participates in together --
    # chaos_to_divine via chaos_leg.suggested_buy_price being nil, and
    # divine_to_chaos via chaos_leg.market_sell_price being <= 0 -- rather
    # than exactly one surviving.
    chaos_leg = snapshot(@chaos, @wisdom, 2, 1, 10, 3, 100, 50, 1, 1)
    divine_leg = snapshot(@divine, @wisdom, 1, 1700, 1, 1900, 30, 80, 1, 1)

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210) == []
  end

  test "divine leg price collapses below one: both directions dropped safely, no crash" do
    # Mirror of the case above: chaos_to_divine uses divine_leg.market_sell_price
    # as its via amount, which feeds into a division against the direct
    # baseline -- an unguarded 0 there produces a crash even though no
    # field is a literal division by the zero itself.
    chaos_leg = snapshot(@chaos, @deck, 1, 8, 1, 13, 100, 50, 1, 1)
    divine_leg = snapshot(@divine, @deck, 2, 1, 10, 3, 100, 50, 1, 1)

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210) == []
  end

  test "rate unavailable returns empty regardless of snapshots" do
    chaos_leg = snapshot(@chaos, @deck, 1, 8, 1, 13, 100, 50, 1, 1)
    divine_leg = snapshot(@divine, @deck, 1, 1700, 1, 1900, 30, 80, 1, 1)

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], nil) == []
  end

  test "no matching divine leg for the same intermediary is not a candidate" do
    chaos_leg = snapshot(@chaos, @deck, 1, 8, 1, 13, 100, 50, 1, 1)

    assert BulkBuyOpportunityFinder.find([chaos_leg], @rate_210) == []
  end

  test "only the chaos/divine reference pair itself excludes it as a candidate" do
    chaos_divine = snapshot(@chaos, @divine, 210, 1, 210, 1, 50, 60, 50, 60)

    assert BulkBuyOpportunityFinder.find([chaos_divine], @rate_210) == []
  end

  test "non-finite ratio on one leg drops that intermediary entirely" do
    # lowest_ratio_a=0
    chaos_leg = snapshot(@chaos, @deck, 0, 8, 1, 13, 100, 50, 1, 1)
    divine_leg = snapshot(@divine, @deck, 1, 1700, 1, 1900, 30, 80, 1, 1)

    assert BulkBuyOpportunityFinder.find([chaos_leg, divine_leg], @rate_210) == []
  end
end
