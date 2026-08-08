defmodule PoeFlipFinder.BulkBuyOpportunityFinder do
  @moduledoc """
  Computes Feature E (Bulk Buy / triangular arbitrage, docs/PRD.md § 7.5)
  opportunities: for any currency X that trades against both Chaos and
  Divine, checks whether buying X with one and reselling it for the other
  beats the direct Chaos<->Divine exchange rate -- evaluated in both
  directions independently, since undercut pricing isn't symmetric (one
  direction can be viable while the reverse isn't).
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
        :error -> []
        {:ok, divine_snapshot} -> opportunities_for(intermediary, chaos_snapshot, divine_snapshot, rate)
      end
    end)
  end

  defp opportunities_for(intermediary, chaos_snapshot, divine_snapshot, rate) do
    chaos_quote = quote_for(chaos_snapshot, BaseCurrencyIds.chaos_external_id())
    divine_quote = quote_for(divine_snapshot, BaseCurrencyIds.divine_external_id())

    if chaos_quote == nil or divine_quote == nil do
      []
    else
      [
        chaos_to_divine(intermediary, chaos_quote, divine_quote, rate),
        divine_to_chaos(intermediary, chaos_quote, divine_quote, rate)
      ]
      |> Enum.reject(&is_nil/1)
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
    currency.external_id in [BaseCurrencyIds.chaos_external_id(), BaseCurrencyIds.divine_external_id()]
  end

  defp quote_for(snapshot, base_external_id) do
    base_is_a? = snapshot.currency_a.external_id == base_external_id

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

  # Buy the intermediary with Chaos, sell it for Divine, compare against the
  # direct Chaos->Divine baseline at the raw, non-undercut, averaged rate --
  # a comparison reference, not an order we're suggesting the user post.
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
  #
  # Scaled so the trade always ends at exactly 1 Divine sold, rather than
  # starting from 1 Chaos: "1 Chaos -> 0.005 Divine" is a meaningless
  # fraction to read, since Chaos is the much smaller-value currency here.
  defp chaos_to_divine(_intermediary, %UndercutQuote{suggested_buy_price: nil}, _divine_quote, _rate), do: nil

  defp chaos_to_divine(_intermediary, _chaos_quote, %UndercutQuote{market_sell_price: price}, _rate) when price <= 0,
    do: nil

  defp chaos_to_divine(intermediary, chaos_quote, divine_quote, rate) do
    sell_amount = 1.0
    # Sells for exactly 1 Divine, by definition.
    via_amount = divine_quote.market_sell_price
    start_amount = via_amount / chaos_quote.suggested_buy_price

    direct_baseline_divine = start_amount / rate.chaos_per_divine
    margin_percent = (sell_amount - direct_baseline_divine) / direct_baseline_divine * 100
    profit_chaos = (sell_amount - direct_baseline_divine) * rate.chaos_per_divine
    volume = min(chaos_quote.buy_leg_stock, divine_quote.buy_leg_stock)

    %FlipOpportunity{
      technique: :bulk_buy,
      start: [%CurrencyAmount{currency: rate.chaos_currency, quantity: start_amount}],
      via: [%CurrencyAmount{currency: intermediary, quantity: via_amount}],
      sell: [%CurrencyAmount{currency: rate.divine_currency, quantity: sell_amount}],
      margin_percent: margin_percent,
      profit: %CurrencyAmount{currency: rate.chaos_currency, quantity: profit_chaos},
      volume: volume,
      detail: detail(chaos_quote.suggested_buy_price, divine_quote.market_sell_price, rate.chaos_per_divine)
    }
  end

  # Buy the intermediary with 1 Divine, sell it for Chaos, compare against
  # the direct Divine->Chaos baseline -- already Chaos-denominated, so the
  # profit figure needs no conversion. Same buy-competitive/sell-market
  # split as chaos_to_divine/4 above.
  defp divine_to_chaos(_intermediary, _chaos_quote, %UndercutQuote{suggested_buy_price: nil}, _rate), do: nil

  defp divine_to_chaos(_intermediary, %UndercutQuote{market_sell_price: price}, _divine_quote, _rate) when price <= 0,
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
