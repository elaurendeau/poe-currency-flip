defmodule PoeFlipFinder.UndercutQuote do
  @moduledoc """
  The realistic, postable buy/sell prices for a currency pair leg, derived
  from the hour's two observed rate extremes (docs/PRD.md § 7.2). Currency
  can't be transacted in fractions, and posting a limit order at the literal
  best-ever observed rate rarely gets filled, so both reference rates are
  floored to whole numbers and then undercut by 1 unit in whichever
  direction makes the posted order more attractive than the going rate to a
  counterparty: the buy price steps down, the sell price steps up.

  `suggested_buy_price` can be `nil` because the -1 undercut can push a
  small reference rate (e.g. buying Divine Orb with a single Chaos Orb)
  below 1, at which point there's no meaningful buy order to suggest.
  `suggested_sell_price` has no such failure mode -- it's always computable
  once the input ratios are finite, regardless of whether this same leg's
  buy price is viable. This asymmetry matters: a caller evaluating a trade
  that only needs this leg's *sell* price (not its buy price) must still
  get a usable quote even when the buy side is empty.

  `market_sell_price` is a second, less aggressive sell reference for a
  genuine one-directional sell of the "via" currency into the base currency
  (used by Bulk Buy, which is dumping a currency it already holds, not
  round-tripping the same pair, per docs/PRD.md § 7.5). It must **not** be
  confused with `suggested_sell_price`: that one targets a patient,
  competitive round trip (buy this pair's cheap extreme, sell back at a
  favorable rate -- the whole premise of Feature B), which makes it the
  *optimistic* case for a one-directional seller, not the conservative one.
  `market_sell_price` instead reuses the hour's *other* real extreme -- the
  same one `suggested_buy_price` is undercut from -- floored with no
  further push, representing the worst of the two real fills seen this hour
  from a seller's perspective.

  `suggested_sell_price` is derived from the hour's **volume-weighted
  average rate** (`total via traded / total start traded`), not the raw
  "other" extreme. A single thin/outlier fill (e.g. one trade at an
  absurd 1:1 rate sitting alongside thousands of trades at the real
  ~1:75 market rate) can make that raw extreme wildly unrepresentative --
  verified against live GGG data 2026-08-08: Jeweller's Orb showed a raw
  lowest/highest ratio pair of 1:75 and 1:1 against Chaos, which floored
  the old "other extreme" sell reference to 2 (`suggested_sell_price`)
  even though the real in-game competitive rate that hour was ~53-66:1.
  The volume-weighted rate is immune to this because a 1-unit outlier fill
  barely moves a total-volume ratio, while it can single-handedly become
  one of only two raw extremes. This average is mathematically guaranteed
  to fall between `lowest_ratio` and `highest_ratio` (a weighted mean of
  per-trade rates using each trade's own `start`-side volume as its
  weight), so it can never produce a `suggested_sell_price` that
  contradicts `suggested_buy_price`'s direction.
  """

  @enforce_keys [:suggested_sell_price, :market_sell_price, :buy_leg_stock]
  defstruct [:suggested_buy_price, :suggested_sell_price, :market_sell_price, :buy_leg_stock]

  @type t :: %__MODULE__{
          suggested_buy_price: float() | nil,
          suggested_sell_price: float(),
          market_sell_price: float(),
          buy_leg_stock: number()
        }

  @doc """
  Resolves an `UndercutQuote` from an hour's raw rate extremes, or `nil`
  when a ratio isn't computable (a zero-rate divisor -- e.g. a zero-volume
  leg, see docs/PRD.md § 7.2's "any opportunity with zero volume is
  dropped" rule, which this guards against one layer down).

  Elixir/Erlang division raises `ArithmeticError` on a zero divisor rather
  than producing `Infinity`/`NaN` the way Java's `double` division does, so
  this checks divisors explicitly instead of dividing first and testing
  finiteness after.
  """
  @spec resolve(number(), number(), number(), number(), number(), number(), number(), number()) ::
          t() | nil
  def resolve(
        lowest_ratio_start,
        lowest_ratio_via,
        highest_ratio_start,
        highest_ratio_via,
        lowest_stock_start,
        highest_stock_start,
        volume_traded_start,
        volume_traded_via
      ) do
    with {:ok, price_at_lowest} <- safe_divide(lowest_ratio_via, lowest_ratio_start),
         {:ok, price_at_highest} <- safe_divide(highest_ratio_via, highest_ratio_start) do
      build_quote(
        price_at_lowest,
        price_at_highest,
        lowest_stock_start,
        highest_stock_start,
        volume_traded_start,
        volume_traded_via
      )
    else
      :error -> nil
    end
  end

  defp safe_divide(_numerator, denominator) when denominator == 0, do: :error
  defp safe_divide(numerator, denominator), do: {:ok, numerator / denominator}

  defp build_quote(
         price_at_lowest,
         price_at_highest,
         lowest_stock_start,
         highest_stock_start,
         volume_traded_start,
         volume_traded_via
       ) do
    buy_at_highest_extreme? = price_at_highest >= price_at_lowest
    raw_buy_price = if buy_at_highest_extreme?, do: price_at_highest, else: price_at_lowest

    other_extreme_price =
      if buy_at_highest_extreme?, do: price_at_lowest, else: price_at_highest

    raw_round_trip_sell_price =
      volume_weighted_price(volume_traded_start, volume_traded_via) || other_extreme_price

    floored_buy_price = Float.floor(raw_buy_price) - 1
    suggested_buy_price = if floored_buy_price >= 1, do: floored_buy_price, else: nil
    suggested_sell_price = Float.floor(raw_round_trip_sell_price) + 1
    market_sell_price = Float.floor(raw_buy_price)
    buy_leg_stock = if buy_at_highest_extreme?, do: highest_stock_start, else: lowest_stock_start

    %__MODULE__{
      suggested_buy_price: suggested_buy_price,
      suggested_sell_price: suggested_sell_price,
      market_sell_price: market_sell_price,
      buy_leg_stock: buy_leg_stock
    }
  end

  # No real trading happened this hour (a zero-volume leg is dropped
  # entirely one layer up, docs/PRD.md § 7.2) -- falls back to the raw
  # extreme rather than dividing by zero.
  defp volume_weighted_price(volume_traded_start, _volume_traded_via)
       when volume_traded_start == 0,
       do: nil

  defp volume_weighted_price(volume_traded_start, volume_traded_via),
    do: volume_traded_via / volume_traded_start
end
