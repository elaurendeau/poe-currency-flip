defmodule PoeFlipFinder.ExchangeSpreadOpportunityFinder do
  @moduledoc """
  Computes Feature B (Exchange Spread/Margin Finder, docs/PRD.md § 7.2)
  opportunities: for each currency pair, compares the instant-fill (buy)
  rate against the competitive (sell) rate, always anchored on Chaos or
  Divine so the flip is one a player can actually act on.

  The zero-volume floor (docs/PRD.md § 7.2/§ 7.5) is deliberately *not*
  applied here -- it's a merge-time rule applied once across every
  technique, not a per-finder rule (see the `FlipOpportunities` context).
  """

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    Currency,
    CurrencyAmount,
    DivineChaosRate,
    FlipOpportunity,
    UndercutQuote
  }

  @spec find([PoeFlipFinder.ExchangeMarketSnapshot.t()], DivineChaosRate.t() | nil) :: [
          FlipOpportunity.t()
        ]
  def find(snapshots, divine_chaos_rate) do
    snapshots
    |> Enum.map(&to_opportunity(&1, divine_chaos_rate))
    |> Enum.reject(&is_nil/1)
  end

  defp to_opportunity(snapshot, divine_chaos_rate) do
    with {:ok, anchor_on_a?} <- resolve_anchor_on_a(snapshot.currency_a, snapshot.currency_b),
         {:ok, quote, inverted?} <- resolve_oriented_quote(snapshot, anchor_on_a?) do
      build_opportunity(snapshot, anchor_on_a?, quote, inverted?, divine_chaos_rate)
    else
      _ -> nil
    end
  end

  # Tries anchoring on the base currency (Chaos/Divine) first -- the normal
  # case, where 1 unit of it buys at least 1 whole unit of the other side.
  # When the item is worth *more* than 1 base-unit instead (docs/PRD.md
  # § 7.2), that quote floors to zero and UndercutQuote rejects it --
  # retries anchored on the item instead (`resolve_quote/2` with
  # `anchor_on_a?` flipped naturally computes that orientation, since it's
  # generic over "which side is base"), the same try-both-directions
  # fallback DivinationCardOpportunityFinder already uses for its own legs
  # (`resolve_oriented_quote/4` there).
  defp resolve_oriented_quote(snapshot, anchor_on_a?) do
    direct = resolve_quote(snapshot, anchor_on_a?)

    if viable?(direct) do
      {:ok, direct, false}
    else
      inverted = resolve_quote(snapshot, not anchor_on_a?)
      if viable?(inverted), do: {:ok, inverted, true}, else: :error
    end
  end

  defp viable?(%UndercutQuote{suggested_buy_price: price}), do: not is_nil(price)
  defp viable?(nil), do: false

  defp resolve_quote(snapshot, anchor_on_a?) do
    UndercutQuote.resolve(
      pick(anchor_on_a?, snapshot.lowest_ratio_a, snapshot.lowest_ratio_b),
      pick(anchor_on_a?, snapshot.lowest_ratio_b, snapshot.lowest_ratio_a),
      pick(anchor_on_a?, snapshot.highest_ratio_a, snapshot.highest_ratio_b),
      pick(anchor_on_a?, snapshot.highest_ratio_b, snapshot.highest_ratio_a),
      pick(anchor_on_a?, snapshot.lowest_stock_a, snapshot.lowest_stock_b),
      pick(anchor_on_a?, snapshot.highest_stock_a, snapshot.highest_stock_b)
    )
  end

  defp build_opportunity(snapshot, anchor_on_a?, quote, inverted?, divine_chaos_rate) do
    start_currency = pick(anchor_on_a?, snapshot.currency_a, snapshot.currency_b)
    via_currency = pick(anchor_on_a?, snapshot.currency_b, snapshot.currency_a)

    {start_amount, via_amount} = quantities(quote, inverted?)
    sell_amount = sell_amount(via_amount, quote.suggested_sell_price, inverted?)
    raw_profit = sell_amount - start_amount
    margin_percent = raw_profit / start_amount * 100

    case resolve_profit_in_chaos(start_currency, raw_profit, divine_chaos_rate) do
      nil ->
        nil

      profit ->
        %FlipOpportunity{
          technique: :exchange_spread,
          start: [%CurrencyAmount{currency: start_currency, quantity: start_amount}],
          via: [%CurrencyAmount{currency: via_currency, quantity: via_amount}],
          sell: [%CurrencyAmount{currency: start_currency, quantity: sell_amount}],
          margin_percent: margin_percent,
          profit: profit,
          start_chaos_equivalent:
            start_chaos_equivalent(start_currency, start_amount, divine_chaos_rate),
          volume: quote.buy_leg_stock,
          detail: detail(quote.suggested_buy_price, quote.suggested_sell_price)
        }
    end
  end

  # Direct: 1 unit of the anchor currency buys `suggested_buy_price` units
  # of the item. Inverted: the item is worth more than 1 anchor-unit, so
  # instead 1 unit of the item costs `suggested_buy_price` units of the
  # anchor currency -- multiplication instead of division, the same
  # "scaled so the trade always ends at exactly 1 X" trick
  # BulkBuyOpportunityFinder's chaos_to_divine/4 already uses, mirroring
  # DivinationCardOpportunityFinder's resale_base_amount/3.
  defp quantities(quote, false), do: {1.0, 1.0 * quote.suggested_buy_price}
  defp quantities(quote, true), do: {1.0 * quote.suggested_buy_price, 1.0}

  defp sell_amount(via_amount, suggested_sell_price, false), do: via_amount / suggested_sell_price
  defp sell_amount(via_amount, suggested_sell_price, true), do: via_amount * suggested_sell_price

  # {:ok, true | false} anchors on Chaos when present, else Divine; :error
  # means neither side is a base currency, so the pair is dropped.
  defp resolve_anchor_on_a(currency_a, currency_b) do
    a_is_chaos? = chaos?(currency_a)
    b_is_chaos? = chaos?(currency_b)
    a_is_base? = a_is_chaos? or divine?(currency_a)
    b_is_base? = b_is_chaos? or divine?(currency_b)

    cond do
      not a_is_base? and not b_is_base? -> :error
      a_is_chaos? -> {:ok, true}
      b_is_chaos? -> {:ok, false}
      # Neither side is Chaos, so whichever is Divine anchors.
      true -> {:ok, a_is_base?}
    end
  end

  defp resolve_profit_in_chaos(%Currency{} = start_currency, raw_profit, divine_chaos_rate) do
    if chaos?(start_currency) do
      %CurrencyAmount{currency: start_currency, quantity: raw_profit}
    else
      # start_currency must be Divine at this point -- the only other base currency.
      case divine_chaos_rate do
        nil ->
          nil

        rate ->
          %CurrencyAmount{
            currency: rate.chaos_currency,
            quantity: raw_profit * rate.chaos_per_divine
          }
      end
    end
  end

  # Mirrors resolve_profit_in_chaos/3's own Chaos-vs-Divine branch rather
  # than delegating straight to DivineChaosRate.to_chaos/3: when
  # start_currency is Chaos, resolve_profit_in_chaos/3 above already
  # succeeds even with a nil rate (no Divine involved), but to_chaos/3
  # requires a real rate struct -- calling it here unconditionally would
  # crash on exactly the case this finder already treats as fine.
  defp start_chaos_equivalent(start_currency, start_amount, divine_chaos_rate) do
    if chaos?(start_currency) do
      start_amount
    else
      DivineChaosRate.to_chaos(divine_chaos_rate, start_currency, start_amount)
    end
  end

  defp chaos?(currency), do: currency.external_id == BaseCurrencyIds.chaos_external_id()
  defp divine?(currency), do: currency.external_id == BaseCurrencyIds.divine_external_id()

  defp pick(true, a, _b), do: a
  defp pick(false, _a, b), do: b

  defp detail(buy_price, sell_price),
    do: "buy #{format_ratio(buy_price)}:1 · sell #{format_ratio(sell_price)}:1"

  defp format_ratio(value) do
    if Float.floor(value) == value do
      value |> trunc() |> Integer.to_string()
    else
      :erlang.float_to_binary(value, decimals: 2)
    end
  end
end
