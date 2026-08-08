defmodule PoeFlipFinder.UndercutQuoteTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.UndercutQuote

  # Ported 1:1 from the Java UndercutQuoteTest -- these are the use cases
  # already drilled and confirmed traceable to docs/PRD.md § 7.2 and § 7.5
  # (see docs/ELIXIR_TEST_MANIFESTO.md § Use-Case Discovery).

  test "chaos/wisdom worked example matches hand-verified Feature B numbers" do
    # Raw extremes 185/366 -> buy floors to 366 then undercuts to 365;
    # suggested_sell_price (Feature B's round-trip-favorable extreme) floors
    # to 185 then undercuts to 186.
    quote = UndercutQuote.resolve(1, 185, 1, 366, 50, 60)

    assert quote.suggested_buy_price == 365.0
    assert quote.suggested_sell_price == 186.0

    # market_sell_price (Bulk Buy's one-directional sell reference) is the
    # SAME extreme as the buy price (366), not the round-trip extreme
    # (185) -- a real one-way seller can't rely on the optimistic
    # round-trip rate, so it floors the buy-side extreme with no undercut.
    assert quote.market_sell_price == 366.0
    # highest_stock_start -- the buy-leg extreme won here.
    assert quote.buy_leg_stock == 60
  end

  test "buy price too small to undercut also collapses market_sell_price" do
    # market_sell_price shares its raw extreme with suggested_buy_price
    # (both = the hour's higher "via per start" extreme), so whenever that
    # shared extreme floors below 1, both collapse together: there is no
    # meaningful buy AND no meaningful realistic sell for this leg.
    quote = UndercutQuote.resolve(2, 2, 2, 3, 40, 70)

    assert quote.suggested_buy_price == nil
    assert quote.suggested_sell_price == 2.0
    # floor(1.5), same raw extreme as the buy side.
    assert quote.market_sell_price == 1.0
    assert quote.buy_leg_stock == 70
  end

  test "non-finite ratio returns nil (whole quote is empty)" do
    assert UndercutQuote.resolve(0, 185, 1, 366, 50, 60) == nil
  end

  test "tied extremes undercuts both legs away from the tied rate" do
    # Cross-checks the existing tied-extremes Feature B test's implied
    # intermediate values: 184/186 - 1 =~ -0.010753 profit, ~-1.0753% margin.
    quote = UndercutQuote.resolve(1, 185, 1, 185, 50, 60)

    assert quote.suggested_buy_price == 184.0
    assert quote.suggested_sell_price == 186.0
    # Extremes tied, so same value either way.
    assert quote.market_sell_price == 185.0
  end

  test "wide spread between extremes: market_sell_price uses the worse one for a seller" do
    # Regression test for a real production bug: a currency (e.g. Orb of
    # Fusing) with a wide in-hour spread against Chaos -- say 9 fusing:1c at
    # one extreme and 17 fusing:1c at the other. The realistic sell
    # reference must be 17 (fewer chaos back per fusing sold -- the worse
    # deal for a seller), not 9 (which is only valid as the OTHER leg of a
    # same-pair round trip, per Feature B). Using 9 here previously made
    # Bulk Buy report an "impossible" sell rate roughly double the worst
    # real one, inflating margin and profit accordingly.
    quote = UndercutQuote.resolve(1, 17, 1, 9, 100, 200)

    # floor(17)-1, the favorable-for-buying extreme.
    assert quote.suggested_buy_price == 16.0
    # Same extreme as buy, not the optimistic 9.
    assert quote.market_sell_price == 17.0
  end
end
