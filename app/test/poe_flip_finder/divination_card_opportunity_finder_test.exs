defmodule PoeFlipFinder.DivinationCardOpportunityFinderTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    Currency,
    DivinationCardOpportunityFinder,
    DivinationCardReward,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    League
  }

  # One test per use case enumerated in docs/PRD.md § 7.3, per
  # docs/ELIXIR_TEST_MANIFESTO.md's Use-Case Discovery Procedure. Ported
  # from the deleted Java DivinationCardOpportunityFinderTest -- see the
  # elixir-migration merge commit history for the original.

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
    external_id: BaseCurrencyIds.chaos_external_id(),
    display_name: "Chaos Orb",
    item_type: :currency
  }
  @divine %Currency{
    id: 2,
    external_id: BaseCurrencyIds.divine_external_id(),
    display_name: "Divine Orb",
    item_type: :currency
  }
  @rate_210 %DivineChaosRate{
    chaos_currency: @chaos,
    divine_currency: @divine,
    chaos_per_divine: 210.0
  }

  defp reward(overrides) do
    defaults = %{
      card: %Currency{external_id: nil, display_name: "Test Card", item_type: :divination_card},
      stack_size: 8,
      reward_currency: %Currency{external_id: nil, display_name: "Test Reward", item_type: :currency},
      reward_quantity: 5,
      predictable: true
    }

    struct(DivinationCardReward, Map.merge(defaults, overrides))
  end

  defp snapshot(currency_a, currency_b, opts \\ []) do
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

  defp card_currency, do: %Currency{external_id: "Metadata/Items/DivinationCards/DivinationCardTest", display_name: "Test Card", item_type: :divination_card}
  defp reward_currency, do: %Currency{external_id: "Metadata/Items/Currency/CurrencyTestReward", display_name: "Test Reward", item_type: :currency}

  test "golden path: hand-verified buy + resale via chaos" do
    # Buy leg: flat 1:5 chaos:card ratio -> suggested_buy_price=4 (card per
    # chaos), buy_leg_stock=100. cost_in_base = stack_size(8)/4 = 2 chaos.
    buy_snapshot = snapshot(@chaos, card_currency(), ratios: {1, 5, 1, 5})

    # Resale leg: flat 1:2 chaos:reward ratio -> market_sell_price=2 (reward
    # per chaos). resale = reward_quantity(5)/2 = 2.5 chaos.
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 2, 1, 2})

    [opportunity] =
      DivinationCardOpportunityFinder.find([buy_snapshot, resale_snapshot], [reward(%{})], @rate_210)

    assert opportunity.technique == :divination_card
    assert opportunity.start == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 2.0}]
    assert opportunity.sell == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 2.5}]
    assert opportunity.profit.quantity == 0.5
    assert opportunity.margin_percent == 25.0
    assert opportunity.volume == 100
    assert opportunity.detail == "≈0.25c per card"
  end

  test "predictable: false cards are always excluded" do
    buy_snapshot = snapshot(@chaos, card_currency())
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 2, 1, 2})

    assert DivinationCardOpportunityFinder.find(
             [buy_snapshot, resale_snapshot],
             [reward(%{predictable: false})],
             @rate_210
           ) == []
  end

  test "no chaos/divine rate: contributes nothing" do
    buy_snapshot = snapshot(@chaos, card_currency())
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 2, 1, 2})

    assert DivinationCardOpportunityFinder.find([buy_snapshot, resale_snapshot], [reward(%{})], nil) == []
  end

  test "buy leg falls back to Divine when no Chaos market exists for the card" do
    buy_snapshot = snapshot(@divine, card_currency())
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 2, 1, 2})

    [opportunity] =
      DivinationCardOpportunityFinder.find([buy_snapshot, resale_snapshot], [reward(%{})], @rate_210)

    assert [%PoeFlipFinder.CurrencyAmount{currency: @divine}] = opportunity.start
  end

  test "missing buy leg (no market in either Chaos or Divine): card silently dropped" do
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 2, 1, 2})

    assert DivinationCardOpportunityFinder.find([resale_snapshot], [reward(%{})], @rate_210) == []
  end

  test "resale leg: reward currency is Chaos itself needs no market lookup" do
    buy_snapshot = snapshot(@chaos, card_currency())

    [opportunity] =
      DivinationCardOpportunityFinder.find(
        [buy_snapshot],
        [reward(%{reward_currency: %Currency{external_id: nil, display_name: "Chaos Orb", item_type: :currency}, reward_quantity: 7})],
        @rate_210
      )

    assert opportunity.sell == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 7}]
  end

  test "resale leg: reward currency is Divine itself converts via chaos_per_divine" do
    buy_snapshot = snapshot(@chaos, card_currency())

    [opportunity] =
      DivinationCardOpportunityFinder.find(
        [buy_snapshot],
        [reward(%{reward_currency: %Currency{external_id: nil, display_name: "Divine Orb", item_type: :currency}, reward_quantity: 2})],
        @rate_210
      )

    assert opportunity.sell == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 420.0}]
  end

  test "resale leg falls back to Divine market when no Chaos market exists for the reward" do
    buy_snapshot = snapshot(@chaos, card_currency())
    # Only a Divine-side market for the reward exists -- flat 1:2 ->
    # market_sell_price=2 (reward per divine). resale = 4/2 * 210 = 420 chaos.
    resale_snapshot = snapshot(@divine, reward_currency(), ratios: {1, 2, 1, 2})

    [opportunity] =
      DivinationCardOpportunityFinder.find(
        [buy_snapshot, resale_snapshot],
        [reward(%{reward_quantity: 4})],
        @rate_210
      )

    assert opportunity.sell == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 420.0}]
  end

  test "missing resale leg (reward has no market against Chaos or Divine): card silently dropped" do
    buy_snapshot = snapshot(@chaos, card_currency())

    assert DivinationCardOpportunityFinder.find([buy_snapshot], [reward(%{})], @rate_210) == []
  end

  test "buy leg re-orients when the card is worth more than 1 Chaos (the Sephirot case)" do
    # Direct orientation (card units per 1 chaos): ratio 200:1 -> price
    # 1/200 = 0.005, floors to 0, suggested_buy_price goes negative -> nil,
    # not viable. Without the fallback this card would be silently dropped
    # despite having a real, tradeable market.
    expensive_card = snapshot(@chaos, card_currency(), ratios: {200, 1, 200, 1}, stocks: {1, 1, 20, 30})
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 2, 1, 2})

    [opportunity] =
      DivinationCardOpportunityFinder.find(
        [expensive_card, resale_snapshot],
        [reward(%{stack_size: 1})],
        @rate_210
      )

    # Inverted orientation (chaos per 1 card): price 200 -> suggested_buy_price
    # = floor(200) - 1 = 199. cost = stack_size(1) * 199 = 199 chaos.
    assert opportunity.start == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 199.0}]
    assert opportunity.volume == 30
  end

  test "resale leg re-orients when the reward is worth more than 1 Chaos" do
    buy_snapshot = snapshot(@chaos, card_currency())
    # Direct orientation (reward per 1 chaos): ratio 200:1 -> price 0.005,
    # market_sell_price floors to 0, not viable (0 is not > 0). Inverted
    # orientation (chaos per 1 reward unit): price 200, market_sell_price=200.
    expensive_reward = snapshot(@chaos, reward_currency(), ratios: {200, 1, 200, 1})

    [opportunity] =
      DivinationCardOpportunityFinder.find(
        [buy_snapshot, expensive_reward],
        [reward(%{reward_quantity: 1})],
        @rate_210
      )

    assert opportunity.sell == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 200.0}]
  end

  test "resale is priced at the market rate, never the round-trip-favorable rate" do
    buy_snapshot = snapshot(@chaos, card_currency())
    # Same shape as the hand-verified Bulk Buy chaos-wisdom fixture:
    # price_at_lowest=185, price_at_highest=366 -> market_sell_price=366,
    # but suggested_sell_price (round-trip) would be floor(185)+1=186.
    # reward_quantity=366 makes the two divisors trivially distinguishable:
    # 366/366=1.0 if market_sell_price is used (correct), 366/186!=1.0 if
    # suggested_sell_price were wrongly used instead.
    resale_snapshot = snapshot(@chaos, reward_currency(), ratios: {1, 185, 1, 366})

    [opportunity] =
      DivinationCardOpportunityFinder.find(
        [buy_snapshot, resale_snapshot],
        [reward(%{reward_quantity: 366})],
        @rate_210
      )

    assert opportunity.sell == [%PoeFlipFinder.CurrencyAmount{currency: @chaos, quantity: 1.0}]
  end
end
