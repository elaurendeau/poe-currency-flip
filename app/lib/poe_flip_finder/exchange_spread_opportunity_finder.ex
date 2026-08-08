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
         quote <- resolve_quote(snapshot, anchor_on_a?),
         %UndercutQuote{suggested_buy_price: suggested_buy_price}
         when not is_nil(suggested_buy_price) <- quote do
      build_opportunity(snapshot, anchor_on_a?, quote, divine_chaos_rate)
    else
      _ -> nil
    end
  end

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

  defp build_opportunity(snapshot, anchor_on_a?, quote, divine_chaos_rate) do
    start_currency = pick(anchor_on_a?, snapshot.currency_a, snapshot.currency_b)
    via_currency = pick(anchor_on_a?, snapshot.currency_b, snapshot.currency_a)

    start_amount = 1.0
    via_amount = start_amount * quote.suggested_buy_price
    sell_amount = via_amount / quote.suggested_sell_price
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
          volume: quote.buy_leg_stock,
          detail: detail(quote.suggested_buy_price, quote.suggested_sell_price)
        }
    end
  end

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
