defmodule PoeFlipFinder.VendorRecipeOpportunityFinder do
  @moduledoc """
  Computes Feature A (Vendor Recipe Arbitrage, docs/PRD.md § 7.1)
  opportunities: buy a currency via the Exchange, run it through a chain of
  1 to 3 vendor recipes (docs/DATA_SOURCES.md § Vendor Sell Rates &
  Recipes), then resell the resulting currency on the Exchange.

  **Chain search:** recipes are edges in a graph keyed by currency display
  name (input -> output). Every simple path (no currency repeated within a
  path, including not returning to the starting currency) of 1 to 3 edges
  is a candidate chain -- capped at 3 to bound the search over the
  currently-small recipe set and keep the rendered "Via" column readable;
  see docs/PRD.md § 7.1 for this as an explicit, documented limit rather
  than an accidental one. Multiple distinct chains between the same two
  currencies (different intermediate hops) are kept as separate
  opportunities, same as every other technique keeps distinct routes
  separate rather than deduplicating to "the best one."

  **Pricing convention**, matching Bulk Buy/Divination Card: the entry leg
  (buying the chain's starting currency on the Exchange) is priced
  competitively (`suggested_buy_price`, undercut -1); the exit leg
  (reselling the chain's ending currency) is priced at the plain
  `market_sell_price` -- a one-directional dump into existing demand, not a
  round-trip order. Both legs independently prefer a Chaos-side market,
  falling back to Divine -- the two legs are unrelated trades. Quantities
  through the recipe chain itself are treated as continuous (a recipe's
  ratio applied fractionally), the same simplification this app already
  applies to Exchange ratios, rather than rounding to whole vendor-sale
  batches.

  Both legs also re-orient (per `UndercutQuote`) if the "other" side turns
  out to be worth more than 1 base unit, exactly as
  `DivinationCardOpportunityFinder` already does for its own two legs.

  `detail` spells out every step of the chain as its own imperative
  instruction ("Buy N X on GE -> vendor for N Y -> ... -> sell Y on GE for
  ~Nc") per docs/PRD.md § 7.1's "show the full step-by-step recipe... so
  the user can execute it manually" -- unlike the other techniques' terser
  detail lines, this one names the GE step and the vendor step(s)
  explicitly rather than leaving them implicit in the Via column's arrows,
  since a Vendor Recipe row mixes two different kinds of transaction (an
  Exchange trade and one or more NPC vendor sales) that look identical as
  a bare currency-to-currency arrow.
  """

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    Currency,
    CurrencyAmount,
    DivineChaosRate,
    ExchangeMarketSnapshot,
    FlipOpportunity,
    FlipOpportunityPresenter,
    UndercutQuote,
    VendorRecipe
  }

  @max_chain_length 3

  @spec find([ExchangeMarketSnapshot.t()], [VendorRecipe.t()], DivineChaosRate.t() | nil) ::
          [FlipOpportunity.t()]
  def find(_snapshots, _vendor_recipes, nil), do: []

  def find(snapshots, vendor_recipes, rate) do
    vendor_recipes
    |> chains()
    |> Enum.map(&to_opportunity(&1, snapshots, rate))
    |> Enum.reject(&is_nil/1)
  end

  # Every simple path of 1..@max_chain_length recipe edges, as a list of
  # `VendorRecipe`, starting from every recipe in turn.
  defp chains(vendor_recipes) do
    by_input = Enum.group_by(vendor_recipes, & &1.input_currency.display_name)

    Enum.flat_map(vendor_recipes, fn first_recipe ->
      visited =
        MapSet.new([first_recipe.input_currency.display_name, first_recipe.output_currency.display_name])

      extend_chain([first_recipe], by_input, visited)
    end)
  end

  defp extend_chain(chain, by_input, visited) do
    if length(chain) >= @max_chain_length do
      [chain]
    else
      last_output = List.last(chain).output_currency.display_name
      next_recipes = Map.get(by_input, last_output, [])

      extensions =
        next_recipes
        |> Enum.reject(&MapSet.member?(visited, &1.output_currency.display_name))
        |> Enum.flat_map(fn next_recipe ->
          extend_chain(
            chain ++ [next_recipe],
            by_input,
            MapSet.put(visited, next_recipe.output_currency.display_name)
          )
        end)

      [chain | extensions]
    end
  end

  defp to_opportunity(chain, snapshots, rate) do
    start_name = List.first(chain).input_currency.display_name
    end_name = List.last(chain).output_currency.display_name

    with {:ok, buy_leg} <- resolve_buy_leg(start_name, snapshots, rate),
         start_units_per_base = start_units_per_base(buy_leg),
         via <- via_amounts(chain, buy_leg, start_units_per_base, snapshots),
         end_quantity = List.last(via).quantity,
         {:ok, sell} <- resolve_sell_leg(end_name, end_quantity, snapshots, rate) do
      build_opportunity(buy_leg, via, sell, rate)
    else
      :error -> nil
    end
  end

  defp build_opportunity(buy_leg, via, sell, rate) do
    cost_chaos = DivineChaosRate.to_chaos(rate, buy_leg.base_currency, 1.0)
    profit_chaos = sell.chaos_amount - cost_chaos
    margin_percent = profit_chaos / cost_chaos * 100

    %FlipOpportunity{
      technique: :vendor_recipe,
      start: [%CurrencyAmount{currency: buy_leg.base_currency, quantity: 1.0}],
      via: via,
      sell: [%CurrencyAmount{currency: rate.chaos_currency, quantity: sell.chaos_amount}],
      margin_percent: margin_percent,
      profit: %CurrencyAmount{currency: rate.chaos_currency, quantity: profit_chaos},
      start_chaos_equivalent: cost_chaos,
      volume: volume(buy_leg.quote.buy_leg_stock, sell.stock),
      detail: detail(via, sell.chaos_amount)
    }
  end

  # The exit leg is only a real, stock-bounded Exchange sell when it goes
  # through a market at all -- when the chain's ending currency literally
  # is Chaos or Divine, there's no second leg to bound volume by, so only
  # the buy leg's stock applies (mirrors DivinationCardOpportunityFinder's
  # identity-reward branches, which don't factor a resale stock in either).
  defp volume(buy_leg_stock, :unbounded), do: buy_leg_stock
  defp volume(buy_leg_stock, sell_stock), do: min(buy_leg_stock, sell_stock)

  defp via_amounts(chain, buy_leg, start_units_per_base, snapshots) do
    start_amount = %CurrencyAmount{currency: buy_leg.unit_currency, quantity: start_units_per_base}

    {amounts, _} =
      Enum.reduce(chain, {[start_amount], start_units_per_base}, fn recipe, {acc, quantity} ->
        next_quantity = quantity / recipe.input_quantity * recipe.output_quantity

        next_currency =
          resolve_display_currency(recipe.output_currency.display_name, snapshots)

        {acc ++ [%CurrencyAmount{currency: next_currency, quantity: next_quantity}], next_quantity}
      end)

    amounts
  end

  defp detail(via, sell_chaos_amount) do
    [first | hops] = via
    last = List.last(via)

    buy_step = "Buy #{quantity(first.quantity)} #{first.currency.display_name} on GE"
    vendor_steps = Enum.map(hops, &"vendor for #{quantity(&1.quantity)} #{&1.currency.display_name}")
    sell_step = "sell #{last.currency.display_name} on GE for #{quantity(sell_chaos_amount)}c"

    Enum.join([buy_step] ++ vendor_steps ++ [sell_step], " → ")
  end

  defp quantity(value), do: FlipOpportunityPresenter.format_quantity(value)

  defp start_units_per_base(%{price_is_per_unit: false, quote: quote}),
    do: quote.suggested_buy_price

  defp start_units_per_base(%{price_is_per_unit: true, quote: quote}),
    do: 1 / quote.suggested_buy_price

  # Prefers a Chaos-side market for the chain's starting currency; falls
  # back to Divine.
  defp resolve_buy_leg(currency_name, snapshots, rate) do
    with :error <-
           find_buy_leg(currency_name, snapshots, BaseCurrencyIds.chaos_external_id(), rate.chaos_currency) do
      find_buy_leg(currency_name, snapshots, BaseCurrencyIds.divine_external_id(), rate.divine_currency)
    end
  end

  defp find_buy_leg(currency_name, snapshots, base_external_id, base_currency) do
    with {snapshot, unit_currency} <-
           find_snapshot_for(currency_name, snapshots, base_external_id) || :error,
         {:ok, quote, inverted?} <-
           resolve_oriented_quote(
             snapshot,
             base_external_id,
             unit_currency.external_id,
             &(&1.suggested_buy_price != nil)
           ) || :error do
      {:ok,
       %{
         base_currency: base_currency,
         unit_currency: unit_currency,
         quote: quote,
         price_is_per_unit: inverted?
       }}
    end
  end

  # Converts the chain's final currency into Chaos. Chaos/Divine endpoints
  # need no market lookup; any other currency needs its own market against
  # Chaos or Divine, priced at market_sell_price (a one-directional dump,
  # per this module's moduledoc) -- Chaos is tried first, Divine is a
  # fallback.
  defp resolve_sell_leg(currency_name, quantity, snapshots, rate) do
    cond do
      currency_name == rate.chaos_currency.display_name ->
        {:ok, %{chaos_amount: quantity, stock: :unbounded}}

      currency_name == rate.divine_currency.display_name ->
        {:ok, %{chaos_amount: quantity * rate.chaos_per_divine, stock: :unbounded}}

      true ->
        with :error <-
               sell_through_market(
                 currency_name,
                 quantity,
                 snapshots,
                 BaseCurrencyIds.chaos_external_id(),
                 1.0
               ) do
          sell_through_market(
            currency_name,
            quantity,
            snapshots,
            BaseCurrencyIds.divine_external_id(),
            rate.chaos_per_divine
          )
        end
    end
  end

  defp sell_through_market(currency_name, quantity, snapshots, base_external_id, chaos_per_base_unit) do
    with {snapshot, _currency} <-
           find_snapshot_for(currency_name, snapshots, base_external_id) || :error,
         {:ok, quote, inverted?} <-
           resolve_oriented_quote(
             snapshot,
             base_external_id,
             currency_external_id(snapshot, currency_name),
             &(&1.market_sell_price > 0)
           ) || :error do
      base_amount = sell_base_amount(quote, quantity, inverted?)
      {:ok, %{chaos_amount: base_amount * chaos_per_base_unit, stock: quote.buy_leg_stock}}
    end
  end

  defp sell_base_amount(quote, quantity, false), do: quantity / quote.market_sell_price
  defp sell_base_amount(quote, quantity, true), do: quantity * quote.market_sell_price

  defp currency_external_id(snapshot, name) do
    case other_currency_by_name(snapshot, name) do
      %{external_id: external_id} -> external_id
      nil -> nil
    end
  end

  defp other_currency_by_name(snapshot, name) do
    cond do
      snapshot.currency_a.display_name == name -> snapshot.currency_a
      snapshot.currency_b.display_name == name -> snapshot.currency_b
      true -> nil
    end
  end

  defp find_snapshot_for(name, snapshots, base_external_id) do
    Enum.find_value(snapshots, fn snapshot ->
      case other_currency(snapshot, base_external_id) do
        %{display_name: ^name} = other -> {snapshot, other}
        _ -> nil
      end
    end)
  end

  # Best-effort icon/external_id resolution for a chain's intermediate
  # currencies (never bought/sold directly, so they don't need to trade
  # against Chaos or Divine specifically) -- any snapshot mentioning the
  # name will do. Falls back to the bundled placeholder Currency (no
  # icon_url) when the currency has no active market at all this
  # generation; the UI already renders that case with no icon.
  defp resolve_display_currency(name, snapshots) do
    Enum.find_value(snapshots, fn snapshot -> other_currency_by_name(snapshot, name) end) ||
      %Currency{id: nil, external_id: nil, display_name: name, icon_url: nil, category: :currency}
  end

  # Tries quoting with `base_external_id` as the base first (direct
  # orientation); if that's not viable (per `viable?`), retries with
  # `other_external_id` as the base instead (inverted orientation). `nil`
  # means neither is viable, or `other_external_id` is unknown (the sell
  # leg's currency wasn't found in this snapshot at all).
  defp resolve_oriented_quote(_snapshot, _base_external_id, nil, _viable?), do: nil

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
      pick(base_is_a?, snapshot.highest_stock_a, snapshot.highest_stock_b),
      pick(base_is_a?, snapshot.volume_traded_a, snapshot.volume_traded_b),
      pick(base_is_a?, snapshot.volume_traded_b, snapshot.volume_traded_a)
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
end
