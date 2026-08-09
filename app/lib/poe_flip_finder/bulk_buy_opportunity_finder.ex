defmodule PoeFlipFinder.BulkBuyOpportunityFinder do
  @moduledoc """
  Computes Feature E (Bulk Buy / triangular arbitrage, docs/PRD.md § 7.5)
  opportunities: for any currency X that trades against both Chaos and
  Divine, checks whether buying X with Divine and reselling it for Chaos
  beats the direct Divine->Chaos exchange rate.

  Only this one direction is computed -- per direct user feedback, the
  reverse (buy with Chaos, resell for Divine) isn't a trade players are
  looking for here, even though it's a real, computable arbitrage. Bulk
  Buy is specifically "convert Divine you're already holding into more
  Chaos than a direct sale would get," not a general two-way triangular
  scan.
  """

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    Currency,
    CurrencyAmount,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    FlipOpportunity,
    UndercutQuote
  }

  @spec find([ExchangeMarketSnapshot.t()], DivineChaosRate.t() | nil) :: [FlipOpportunity.t()]
  def find(_snapshots, nil), do: []

  def find(snapshots, rate) do
    chaos_legs = legs_by_other_currency(snapshots, BaseCurrencyIds.chaos_external_id())
    divine_legs = legs_by_other_currency(snapshots, BaseCurrencyIds.divine_external_id())

    Enum.flat_map(chaos_legs, fn {intermediary, chaos_snapshot} ->
      case Map.fetch(divine_legs, intermediary) do
        :error ->
          []

        {:ok, divine_snapshot} ->
          opportunities_for(intermediary, chaos_snapshot, divine_snapshot, rate)
      end
    end)
  end

  defp opportunities_for(intermediary, chaos_snapshot, divine_snapshot, rate) do
    chaos_quote = quote_for(chaos_snapshot, BaseCurrencyIds.chaos_external_id())
    divine_quote = quote_for(divine_snapshot, BaseCurrencyIds.divine_external_id())

    if chaos_quote == nil or divine_quote == nil do
      []
    else
      case divine_to_chaos(intermediary, chaos_quote, divine_quote, rate) do
        nil -> []
        opportunity -> [opportunity]
      end
    end
  end

  # All snapshots where one side is the given base currency, keyed by the
  # other ("intermediary") side -- excluding the base-to-base reference
  # pair itself (e.g. Chaos<->Divine), which isn't a valid intermediary.
  @spec legs_by_other_currency([ExchangeMarketSnapshot.t()], String.t()) ::
          %{Currency.t() => ExchangeMarketSnapshot.t()}
  defp legs_by_other_currency(snapshots, base_external_id) do
    Enum.reduce(snapshots, %{}, fn snapshot, legs ->
      add_leg(legs, other_currency(snapshot, base_external_id), snapshot)
    end)
  end

  defp add_leg(legs, nil, _snapshot), do: legs

  defp add_leg(legs, other, snapshot) do
    if base_currency?(other), do: legs, else: Map.put(legs, other, snapshot)
  end

  defp other_currency(snapshot, base_external_id) do
    cond do
      snapshot.currency_a.external_id == base_external_id -> snapshot.currency_b
      snapshot.currency_b.external_id == base_external_id -> snapshot.currency_a
      true -> nil
    end
  end

  defp base_currency?(currency) do
    currency.external_id in [
      BaseCurrencyIds.chaos_external_id(),
      BaseCurrencyIds.divine_external_id()
    ]
  end

  defp quote_for(snapshot, base_external_id) do
    base_is_a? = snapshot.currency_a.external_id == base_external_id

    UndercutQuote.resolve(
      pick(base_is_a?, snapshot.lowest_ratio_a, snapshot.lowest_ratio_b),
      pick(base_is_a?, snapshot.lowest_ratio_b, snapshot.lowest_ratio_a),
      pick(base_is_a?, snapshot.highest_ratio_a, snapshot.highest_ratio_b),
      pick(base_is_a?, snapshot.highest_ratio_b, snapshot.highest_ratio_a),
      pick(base_is_a?, snapshot.lowest_stock_a, snapshot.lowest_stock_b),
      pick(base_is_a?, snapshot.highest_stock_a, snapshot.highest_stock_b),
      pick(base_is_a?, snapshot.volume_traded_a, snapshot.volume_traded_b),
      pick(base_is_a?, snapshot.volume_traded_b, snapshot.volume_traded_a)
    )
  end

  defp pick(true, a, _b), do: a
  defp pick(false, _a, b), do: b

  # Buy the intermediary with 1 Divine, sell it for Chaos, compare against
  # the direct Divine->Chaos baseline -- already Chaos-denominated, so the
  # profit figure needs no conversion.
  #
  # The buy leg uses suggested_buy_price (a competitive limit order,
  # undercut -1) but the sell leg uses market_sell_price -- see
  # UndercutQuote for why that is the hour's worse-for-a-seller extreme, not
  # suggested_sell_price's round-trip-favorable one. Posting two unfilled
  # limit orders back to back on a large, often-illiquid intermediary stack
  # is also a bigger risk than posting one, so only the entry is priced
  # competitively; the exit assumes dumping into demand that's already been
  # shown to exist, at worst at the less generous of the hour's two real
  # rates.
  defp divine_to_chaos(
         _intermediary,
         _chaos_quote,
         %UndercutQuote{suggested_buy_price: nil},
         _rate
       ),
       do: nil

  defp divine_to_chaos(
         _intermediary,
         %UndercutQuote{market_sell_price: price},
         _divine_quote,
         _rate
       )
       when price <= 0,
       do: nil

  defp divine_to_chaos(intermediary, chaos_quote, divine_quote, rate) do
    via_amount = divine_quote.suggested_buy_price
    sell_amount_chaos = via_amount / chaos_quote.market_sell_price
    direct_baseline_chaos = rate.chaos_per_divine
    margin_percent = (sell_amount_chaos - direct_baseline_chaos) / direct_baseline_chaos * 100
    profit_chaos = sell_amount_chaos - direct_baseline_chaos
    volume = min(divine_quote.buy_leg_stock, chaos_quote.buy_leg_stock)

    %FlipOpportunity{
      technique: :bulk_buy,
      start: [%CurrencyAmount{currency: rate.divine_currency, quantity: 1.0}],
      via: [%CurrencyAmount{currency: intermediary, quantity: via_amount}],
      sell: [%CurrencyAmount{currency: rate.chaos_currency, quantity: sell_amount_chaos}],
      margin_percent: margin_percent,
      profit: %CurrencyAmount{currency: rate.chaos_currency, quantity: profit_chaos},
      start_chaos_equivalent: DivineChaosRate.to_chaos(rate, rate.divine_currency, 1.0),
      volume: volume,
      detail: detail(via_amount, chaos_quote.market_sell_price, rate.chaos_per_divine)
    }
  end

  defp detail(buy_price, sell_price, chaos_per_divine) do
    "buy #{format_ratio(buy_price)}:1 · sell #{format_ratio(sell_price)}:1 · direct ~#{format_ratio(chaos_per_divine)} c/div"
  end

  defp format_ratio(value) do
    if Float.floor(value) == value do
      value |> trunc() |> Integer.to_string()
    else
      :erlang.float_to_binary(value, decimals: 2)
    end
  end
end
