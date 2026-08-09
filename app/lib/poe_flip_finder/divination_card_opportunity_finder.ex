defmodule PoeFlipFinder.DivinationCardOpportunityFinder do
  @moduledoc """
  Computes Feature C (Divination Card Flip Finder, docs/PRD.md § 7.3)
  opportunities: buy a full stack of a predictable-reward card via the
  Exchange, turn it in, and resell the fixed reward for Chaos.

  Matches cards and reward currencies against active snapshots by
  `Currency.display_name`, not `external_id` -- the reference data
  (docs/DATA_SOURCES.md § Divination Card Turn-In Rewards) has no reliable
  source for GGG's internal item paths, only human-readable names captured
  from the PoE Wiki.

  Both the buy leg (which base currency the card itself trades against) and
  the resale leg (which base currency the reward trades against) prefer a
  Chaos market and fall back to Divine independently -- the two legs are
  unrelated trades and one's base doesn't constrain the other's. The buy
  leg is priced competitively (`suggested_buy_price`, same convention every
  other technique's entry leg uses). The resale leg is priced at
  `market_sell_price` -- never the round-trip-favorable
  `suggested_sell_price` -- since this is a one-directional sell into
  existing demand, not a round-trip order, the same reasoning
  `BulkBuyOpportunityFinder` already applies to its own exit leg.

  Both legs also re-orient if the "other" side turns out to be worth more
  than 1 base unit. Quoting "card/reward units per 1 Chaos" floors to 0 for
  something worth, say, 200 Chaos, and the -1 competitive undercut then
  pushes it negative -- `suggested_buy_price`/`market_sell_price` come back
  unusable and the whole opportunity would be silently dropped even for a
  card genuinely trading with real volume and stock (a real production
  incident this guards against, docs/PRD.md § 7.3). When that happens, the
  leg retries with the *other* currency as the base instead ("Chaos per 1
  card" / "Chaos per 1 reward unit"), scaling by multiplication instead of
  division -- an auto-detected fallback per leg, not a hardcoded direction.
  """

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    CurrencyAmount,
    DivinationCardReward,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    FlipOpportunity,
    UndercutQuote
  }

  @spec find([ExchangeMarketSnapshot.t()], [DivinationCardReward.t()], DivineChaosRate.t() | nil) ::
          [FlipOpportunity.t()]
  def find(_snapshots, _card_rewards, nil), do: []

  def find(snapshots, card_rewards, rate) do
    card_rewards
    |> Enum.filter(& &1.predictable)
    |> Enum.map(&to_opportunity(&1, snapshots, rate))
    |> Enum.reject(&is_nil/1)
  end

  defp to_opportunity(reward, snapshots, rate) do
    with {:ok, buy_leg} <- resolve_buy_leg(reward.card.display_name, snapshots, rate),
         {:ok, resale} <-
           resale_value_in_chaos(reward.reward_currency, reward.reward_quantity, snapshots, rate) do
      build_opportunity(reward, buy_leg, resale, rate)
    else
      :error -> nil
    end
  end

  defp build_opportunity(reward, buy_leg, resale, rate) do
    cost_in_base = cost_in_base(buy_leg, reward.stack_size)
    cost_chaos = DivineChaosRate.to_chaos(rate, buy_leg.base_currency, cost_in_base)
    profit_chaos = resale.chaos_amount - cost_chaos
    margin_percent = profit_chaos / cost_chaos * 100

    %FlipOpportunity{
      technique: :divination_card,
      start: [%CurrencyAmount{currency: buy_leg.base_currency, quantity: cost_in_base}],
      via: [
        %CurrencyAmount{currency: buy_leg.card_currency, quantity: reward.stack_size},
        %CurrencyAmount{currency: resale.reward_currency, quantity: reward.reward_quantity}
      ],
      sell: [%CurrencyAmount{currency: rate.chaos_currency, quantity: resale.chaos_amount}],
      margin_percent: margin_percent,
      profit: %CurrencyAmount{currency: rate.chaos_currency, quantity: profit_chaos},
      start_chaos_equivalent: cost_chaos,
      volume: buy_leg.quote.buy_leg_stock,
      detail: "≈#{format_ratio(cost_chaos / reward.stack_size)}c per card"
    }
  end

  defp cost_in_base(%{price_is_per_card: true} = leg, stack_size),
    do: stack_size * leg.quote.suggested_buy_price

  defp cost_in_base(%{price_is_per_card: false} = leg, stack_size),
    do: stack_size / leg.quote.suggested_buy_price

  # Prefers a Chaos-side market for the card; falls back to Divine.
  defp resolve_buy_leg(card_name, snapshots, rate) do
    with :error <-
           find_leg(
             card_name,
             snapshots,
             BaseCurrencyIds.chaos_external_id(),
             rate.chaos_currency
           ) do
      find_leg(card_name, snapshots, BaseCurrencyIds.divine_external_id(), rate.divine_currency)
    end
  end

  defp find_leg(card_name, snapshots, base_external_id, base_currency) do
    with {snapshot, card_currency} <-
           find_snapshot_for(card_name, snapshots, base_external_id) || :error,
         {:ok, quote, price_is_per_card} <-
           resolve_oriented_quote(
             snapshot,
             base_external_id,
             card_currency.external_id,
             &(&1.suggested_buy_price != nil)
           ) || :error do
      {:ok,
       %{
         base_currency: base_currency,
         card_currency: card_currency,
         quote: quote,
         price_is_per_card: price_is_per_card
       }}
    end
  end

  # Converts the card's fixed reward into Chaos. Chaos rewards need no
  # conversion; Divine rewards use the same averaged reference rate Bulk
  # Buy and Exchange Spread already rely on for cross-currency profit
  # normalization; any other reward currency needs its own market against
  # Chaos or Divine, priced at market_sell_price per this module's
  # moduledoc -- Chaos is tried first, Divine is a fallback (some
  # currencies trade mainly against Divine rather than Chaos; without this
  # fallback a card whose reward only has a live Divine market would be
  # silently dropped even though its buy leg resolves fine via the same
  # Divine fallback the buy leg already has).
  defp resale_value_in_chaos(reward_currency, reward_quantity, snapshots, rate) do
    reward_name = reward_currency.display_name

    cond do
      reward_name == rate.chaos_currency.display_name ->
        {:ok, %{reward_currency: rate.chaos_currency, chaos_amount: reward_quantity}}

      reward_name == rate.divine_currency.display_name ->
        {:ok,
         %{
           reward_currency: rate.divine_currency,
           chaos_amount: reward_quantity * rate.chaos_per_divine
         }}

      true ->
        with :error <-
               resale_through_market(
                 reward_name,
                 reward_quantity,
                 snapshots,
                 BaseCurrencyIds.chaos_external_id(),
                 1.0
               ) do
          resale_through_market(
            reward_name,
            reward_quantity,
            snapshots,
            BaseCurrencyIds.divine_external_id(),
            rate.chaos_per_divine
          )
        end
    end
  end

  # `chaos_per_base_unit` converts the base currency's own market-rate
  # proceeds into Chaos -- 1.0 when the base already is Chaos, `chaos_per_divine`
  # when the base is Divine.
  defp resale_through_market(
         reward_name,
         reward_quantity,
         snapshots,
         base_external_id,
         chaos_per_base_unit
       ) do
    with {snapshot, reward_currency} <-
           find_snapshot_for(reward_name, snapshots, base_external_id) || :error,
         {:ok, quote, inverted?} <-
           resolve_oriented_quote(
             snapshot,
             base_external_id,
             reward_currency.external_id,
             &(&1.market_sell_price > 0)
           ) || :error do
      base_amount = resale_base_amount(quote, reward_quantity, inverted?)
      {:ok, %{reward_currency: reward_currency, chaos_amount: base_amount * chaos_per_base_unit}}
    end
  end

  defp resale_base_amount(quote, reward_quantity, false),
    do: reward_quantity / quote.market_sell_price

  defp resale_base_amount(quote, reward_quantity, true),
    do: reward_quantity * quote.market_sell_price

  defp find_snapshot_for(name, snapshots, base_external_id) do
    Enum.find_value(snapshots, fn snapshot ->
      case other_currency(snapshot, base_external_id) do
        %{display_name: ^name} = other -> {snapshot, other}
        _ -> nil
      end
    end)
  end

  # Tries quoting with `base_external_id` as the base first (direct
  # orientation); if that's not viable (per `viable?`), retries with
  # `other_external_id` as the base instead (inverted orientation) -- see
  # this module's moduledoc for why both are tried. `nil` means neither is
  # viable.
  defp resolve_oriented_quote(snapshot, base_external_id, other_external_id, viable?) do
    direct = quote_treating_as_base(snapshot, base_external_id)

    if direct != nil and viable?.(direct) do
      {:ok, direct, false}
    else
      inverted = quote_treating_as_base(snapshot, other_external_id)

      if inverted != nil and viable?.(inverted) do
        {:ok, inverted, true}
      else
        nil
      end
    end
  end

  defp quote_treating_as_base(snapshot, target_external_id) do
    base_is_a? = snapshot.currency_a.external_id == target_external_id

    UndercutQuote.resolve(
      pick(base_is_a?, snapshot.lowest_ratio_a, snapshot.lowest_ratio_b),
      pick(base_is_a?, snapshot.lowest_ratio_b, snapshot.lowest_ratio_a),
      pick(base_is_a?, snapshot.highest_ratio_a, snapshot.highest_ratio_b),
      pick(base_is_a?, snapshot.highest_ratio_b, snapshot.highest_ratio_a),
      pick(base_is_a?, snapshot.lowest_stock_a, snapshot.lowest_stock_b),
      pick(base_is_a?, snapshot.highest_stock_a, snapshot.highest_stock_b)
    )
  end

  defp pick(true, a, _b), do: a
  defp pick(false, _a, b), do: b

  defp other_currency(snapshot, base_external_id) do
    cond do
      snapshot.currency_a.external_id == base_external_id -> snapshot.currency_b
      snapshot.currency_b.external_id == base_external_id -> snapshot.currency_a
      true -> nil
    end
  end

  defp format_ratio(value) do
    if Float.floor(value) == value do
      value |> trunc() |> Integer.to_string()
    else
      :erlang.float_to_binary(value, decimals: 2)
    end
  end
end
