defmodule PoeFlipFinder.VendorRecipeOpportunityFinderTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    Currency,
    CurrencyAmount,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    League,
    VendorRecipe,
    VendorRecipeOpportunityFinder
  }

  # One test per use case enumerated in docs/PRD.md § 7.1, per
  # docs/ELIXIR_TEST_MANIFESTO.md's Use-Case Discovery Procedure.

  @now ~U[2026-08-09 12:00:00Z]
  @league %League{
    id: 1,
    external_id: "Standard",
    display_name: "Standard",
    is_current: false,
    has_exchange_activity: true
  }
  @chaos %Currency{
    id: 1,
    external_id: BaseCurrencyIds.chaos_external_id(),
    display_name: "Chaos Orb",
    category: :currency
  }
  @divine %Currency{
    id: 2,
    external_id: BaseCurrencyIds.divine_external_id(),
    display_name: "Divine Orb",
    category: :currency
  }
  @rate_210 %DivineChaosRate{
    chaos_currency: @chaos,
    divine_currency: @divine,
    chaos_per_divine: 210.0
  }

  defp snapshot(currency_a, currency_b, opts) do
    ratios = Keyword.get(opts, :ratios, {1, 5, 1, 5})
    {ra, rb, ra2, rb2} = ratios
    stocks = Keyword.get(opts, :stocks, {100, 100, 1, 1})
    {sa_lo, sa_hi, sb_lo, sb_hi} = stocks

    %ExchangeMarketSnapshot{
      id: 1,
      generation_id: 999,
      league: @league,
      currency_a: currency_a,
      currency_b: currency_b,
      snapshot_hour: @now,
      volume_traded_a: 100,
      volume_traded_b: 100,
      lowest_stock_a: sa_lo,
      highest_stock_a: sa_hi,
      lowest_stock_b: sb_lo,
      highest_stock_b: sb_hi,
      lowest_ratio_a: ra,
      highest_ratio_a: ra2,
      lowest_ratio_b: rb,
      highest_ratio_b: rb2
    }
  end

  defp placeholder(name), do: %Currency{external_id: nil, display_name: name, category: :currency}

  defp recipe(input_name, input_quantity, output_name, output_quantity) do
    %VendorRecipe{
      input_currency: placeholder(input_name),
      input_quantity: input_quantity,
      output_currency: placeholder(output_name),
      output_quantity: output_quantity
    }
  end

  defp wisdom, do: %Currency{external_id: "Metadata/Items/Currency/CurrencyIdentification", display_name: "Wisdom", category: :currency}
  defp portal, do: %Currency{external_id: "Metadata/Items/Currency/CurrencyPortal", display_name: "Portal", category: :currency}
  defp transmutation, do: %Currency{external_id: "Metadata/Items/Currency/CurrencyUpgradeToMagic", display_name: "Transmutation", category: :currency}
  defp widget, do: %Currency{external_id: "Metadata/Items/Currency/CurrencyWidget", display_name: "Widget", category: :currency}

  test "golden path: hand-verified single-hop chain" do
    # Buy leg: flat 1:5 chaos:wisdom -> suggested_buy_price=4 (wisdom per
    # chaos), buy_leg_stock=100.
    buy_snapshot = snapshot(@chaos, wisdom(), ratios: {1, 5, 1, 5})
    # Sell leg: flat 1:2 chaos:portal -> market_sell_price=2 (portal per
    # chaos), buy_leg_stock=100.
    sell_snapshot = snapshot(@chaos, portal(), ratios: {1, 2, 1, 2})
    recipes = [recipe("Wisdom", 4, "Portal", 1)]

    [opportunity] =
      VendorRecipeOpportunityFinder.find([buy_snapshot, sell_snapshot], recipes, @rate_210)

    assert opportunity.technique == :vendor_recipe
    assert opportunity.start == [%CurrencyAmount{currency: @chaos, quantity: 1.0}]

    assert opportunity.via == [
             %CurrencyAmount{currency: wisdom(), quantity: 4.0},
             %CurrencyAmount{currency: portal(), quantity: 1.0}
           ]

    assert opportunity.sell == [%CurrencyAmount{currency: @chaos, quantity: 0.5}]
    assert opportunity.profit.quantity == -0.5
    assert opportunity.margin_percent == -50.0
    assert opportunity.volume == 100
    assert opportunity.detail == "Buy 4 Wisdom on GE → vendor for 1 Portal → sell Portal on GE for ≈0.5c"
  end

  test "no chaos/divine rate: contributes nothing" do
    buy_snapshot = snapshot(@chaos, wisdom(), ratios: {1, 5, 1, 5})
    sell_snapshot = snapshot(@chaos, portal(), ratios: {1, 2, 1, 2})
    recipes = [recipe("Wisdom", 4, "Portal", 1)]

    assert VendorRecipeOpportunityFinder.find([buy_snapshot, sell_snapshot], recipes, nil) == []
  end

  test "buy leg falls back to Divine when no Chaos market exists for the starting currency" do
    buy_snapshot = snapshot(@divine, wisdom(), ratios: {1, 5, 1, 5})
    sell_snapshot = snapshot(@chaos, portal(), ratios: {1, 2, 1, 2})
    recipes = [recipe("Wisdom", 4, "Portal", 1)]

    [opportunity] =
      VendorRecipeOpportunityFinder.find([buy_snapshot, sell_snapshot], recipes, @rate_210)

    assert [%CurrencyAmount{currency: @divine}] = opportunity.start
  end

  test "missing buy leg (no market in either Chaos or Divine): chain silently dropped" do
    sell_snapshot = snapshot(@chaos, portal(), ratios: {1, 2, 1, 2})
    recipes = [recipe("Wisdom", 4, "Portal", 1)]

    assert VendorRecipeOpportunityFinder.find([sell_snapshot], recipes, @rate_210) == []
  end

  test "sell leg: ending currency is Chaos itself needs no market lookup" do
    buy_snapshot = snapshot(@chaos, widget(), ratios: {1, 5, 1, 5})
    recipes = [recipe("Widget", 4, "Chaos Orb", 7)]

    [opportunity] = VendorRecipeOpportunityFinder.find([buy_snapshot], recipes, @rate_210)

    assert opportunity.sell == [%CurrencyAmount{currency: @chaos, quantity: 7.0}]
    assert opportunity.profit.quantity == 6.0
    assert opportunity.margin_percent == 600.0
    # No second leg to bound volume by -- falls back to the buy leg's own
    # stock alone.
    assert opportunity.volume == 100
  end

  test "sell leg: ending currency is Divine itself converts via chaos_per_divine" do
    buy_snapshot = snapshot(@chaos, widget(), ratios: {1, 5, 1, 5})
    recipes = [recipe("Widget", 4, "Divine Orb", 1)]

    [opportunity] = VendorRecipeOpportunityFinder.find([buy_snapshot], recipes, @rate_210)

    assert opportunity.sell == [%CurrencyAmount{currency: @chaos, quantity: 210.0}]
  end

  test "sell leg falls back to Divine market when no Chaos market exists for the ending currency" do
    buy_snapshot = snapshot(@chaos, widget(), ratios: {1, 5, 1, 5})
    sell_snapshot = snapshot(@divine, portal(), ratios: {1, 2, 1, 2})
    recipes = [recipe("Widget", 4, "Portal", 1)]

    [opportunity] =
      VendorRecipeOpportunityFinder.find([buy_snapshot, sell_snapshot], recipes, @rate_210)

    assert opportunity.sell == [%CurrencyAmount{currency: @chaos, quantity: 105.0}]
  end

  test "missing sell leg (ending currency has no market against Chaos or Divine): chain silently dropped" do
    buy_snapshot = snapshot(@chaos, widget(), ratios: {1, 5, 1, 5})
    recipes = [recipe("Widget", 4, "Portal", 1)]

    assert VendorRecipeOpportunityFinder.find([buy_snapshot], recipes, @rate_210) == []
  end

  test "two-hop chain composes recipe ratios across both hops" do
    buy_snapshot = snapshot(@chaos, wisdom(), ratios: {1, 5, 1, 5})
    sell_snapshot = snapshot(@chaos, transmutation(), ratios: {1, 2, 1, 2})

    recipes = [
      recipe("Wisdom", 4, "Portal", 1),
      recipe("Portal", 1, "Transmutation", 7)
    ]

    [opportunity] =
      VendorRecipeOpportunityFinder.find([buy_snapshot, sell_snapshot], recipes, @rate_210)

    # No live market at all for "Portal" in this fixture -- it only appears
    # as an intermediate hop, so it renders with the placeholder (no icon).
    assert opportunity.via == [
             %CurrencyAmount{currency: wisdom(), quantity: 4.0},
             %CurrencyAmount{currency: placeholder("Portal"), quantity: 1.0},
             %CurrencyAmount{currency: transmutation(), quantity: 7.0}
           ]

    assert opportunity.sell == [%CurrencyAmount{currency: @chaos, quantity: 3.5}]
    assert opportunity.profit.quantity == 2.5
    assert opportunity.margin_percent == 250.0

    assert opportunity.detail ==
             "Buy 4 Wisdom on GE → vendor for 1 Portal → vendor for 7 Transmutation → sell Transmutation on GE for ≈3.5c"
  end

  test "chains longer than 3 hops are not explored beyond the cap" do
    # Linear graph A -> B -> C -> D -> E (4 hops end to end). Every node
    # has a Chaos market so no chain fails for lack of a buy/sell leg --
    # isolating the cap itself as the only thing that can prevent a chain.
    a = %Currency{external_id: "Metadata/Items/Currency/A", display_name: "A", category: :currency}
    b = %Currency{external_id: "Metadata/Items/Currency/B", display_name: "B", category: :currency}
    c = %Currency{external_id: "Metadata/Items/Currency/C", display_name: "C", category: :currency}
    d = %Currency{external_id: "Metadata/Items/Currency/D", display_name: "D", category: :currency}
    e = %Currency{external_id: "Metadata/Items/Currency/E", display_name: "E", category: :currency}

    snapshots =
      Enum.map([a, b, c, d, e], &snapshot(@chaos, &1, ratios: {1, 2, 1, 2}))

    recipes = [
      recipe("A", 1, "B", 1),
      recipe("B", 1, "C", 1),
      recipe("C", 1, "D", 1),
      recipe("D", 1, "E", 1)
    ]

    opportunities = VendorRecipeOpportunityFinder.find(snapshots, recipes, @rate_210)
    via_names = fn o -> Enum.map(o.via, & &1.currency.display_name) end

    # A 3-hop chain (within the cap) is found...
    assert Enum.any?(opportunities, &(via_names.(&1) == ["A", "B", "C", "D"]))
    # ...but the 4-hop chain needed to reach E starting from A never is.
    refute Enum.any?(opportunities, &(via_names.(&1) == ["A", "B", "C", "D", "E"]))
  end

  test "a chain never revisits a currency, including looping back to its own start" do
    a = %Currency{external_id: "Metadata/Items/Currency/A", display_name: "A", category: :currency}
    b = %Currency{external_id: "Metadata/Items/Currency/B", display_name: "B", category: :currency}
    snapshots = [snapshot(@chaos, a, ratios: {1, 4, 1, 4}), snapshot(@chaos, b, ratios: {1, 4, 1, 4})]
    recipes = [recipe("A", 1, "B", 1), recipe("B", 1, "A", 1)]

    opportunities = VendorRecipeOpportunityFinder.find(snapshots, recipes, @rate_210)
    via_names = Enum.map(opportunities, fn o -> Enum.map(o.via, & &1.currency.display_name) end)

    assert Enum.sort(via_names) == Enum.sort([["A", "B"], ["B", "A"]])
  end

  test "multiple recipes sharing an input currency each produce a separate chain" do
    a = %Currency{external_id: "Metadata/Items/Currency/A", display_name: "A", category: :currency}
    b = %Currency{external_id: "Metadata/Items/Currency/B", display_name: "B", category: :currency}
    c = %Currency{external_id: "Metadata/Items/Currency/C", display_name: "C", category: :currency}

    snapshots = [
      snapshot(@chaos, a, ratios: {1, 4, 1, 4}),
      snapshot(@chaos, b, ratios: {1, 2, 1, 2}),
      snapshot(@chaos, c, ratios: {1, 2, 1, 2})
    ]

    recipes = [recipe("A", 1, "B", 1), recipe("A", 1, "C", 1)]

    opportunities = VendorRecipeOpportunityFinder.find(snapshots, recipes, @rate_210)
    via_names = Enum.map(opportunities, fn o -> Enum.map(o.via, & &1.currency.display_name) end)

    assert Enum.sort(via_names) == Enum.sort([["A", "B"], ["A", "C"]])
  end

  test "buy leg re-orients when the starting currency is worth more than 1 Chaos" do
    # Direct orientation (widget units per 1 chaos): ratio 200:1 -> price
    # 1/200, floors to 0, suggested_buy_price goes negative -> nil, not
    # viable. Inverted orientation (chaos per 1 widget): price 200 ->
    # suggested_buy_price = floor(200) - 1 = 199.
    expensive_start =
      snapshot(@chaos, widget(), ratios: {200, 1, 200, 1}, stocks: {1, 1, 20, 30})

    recipes = [recipe("Widget", 1, "Chaos Orb", 1)]

    [opportunity] = VendorRecipeOpportunityFinder.find([expensive_start], recipes, @rate_210)

    assert hd(opportunity.via).quantity == 1 / 199
    assert opportunity.volume == 30
  end

  test "sell leg re-orients when the ending currency is worth more than 1 Chaos" do
    buy_snapshot = snapshot(@chaos, widget(), ratios: {1, 5, 1, 5})
    # Direct orientation (portal per 1 chaos): price 0.005, market_sell_price
    # floors to 0, not viable. Inverted orientation (chaos per 1 portal):
    # price 200, market_sell_price = 200.
    expensive_end = snapshot(@chaos, portal(), ratios: {200, 1, 200, 1})
    recipes = [recipe("Widget", 4, "Portal", 1)]

    [opportunity] =
      VendorRecipeOpportunityFinder.find([buy_snapshot, expensive_end], recipes, @rate_210)

    assert opportunity.sell == [%CurrencyAmount{currency: @chaos, quantity: 200.0}]
  end

  test "volume is the minimum of the buy and sell legs' stock" do
    buy_snapshot = snapshot(@chaos, widget(), ratios: {1, 5, 1, 5}, stocks: {50, 60, 1, 1})
    sell_snapshot = snapshot(@chaos, portal(), ratios: {1, 2, 1, 2}, stocks: {100, 25, 1, 1})
    recipes = [recipe("Widget", 4, "Portal", 1)]

    [opportunity] =
      VendorRecipeOpportunityFinder.find([buy_snapshot, sell_snapshot], recipes, @rate_210)

    assert opportunity.volume == 25
  end
end
