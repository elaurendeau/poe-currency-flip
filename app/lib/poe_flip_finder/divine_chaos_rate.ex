defmodule PoeFlipFinder.DivineChaosRate do
  @moduledoc """
  The Chaos<->Divine exchange rate for a league's active generation,
  averaged from the hour's two rate extremes -- a point-estimate "fair
  value" for normalizing profit figures, not a proposed trade. Used to
  convert Divine-denominated amounts into Chaos (Exchange Spread) and to
  benchmark the direct rate a Bulk Buy opportunity must beat.
  """

  alias PoeFlipFinder.{BaseCurrencyIds, Currency, ExchangeMarketSnapshot}

  @enforce_keys [:chaos_currency, :divine_currency, :chaos_per_divine]
  defstruct [:chaos_currency, :divine_currency, :chaos_per_divine]

  @type t :: %__MODULE__{
          chaos_currency: Currency.t(),
          divine_currency: Currency.t(),
          chaos_per_divine: float()
        }

  @doc """
  Finds the Chaos<->Divine snapshot among an active generation's snapshots
  and averages its two rate extremes into a point-estimate rate, or `nil`
  if no such pair is present this generation.
  """
  @spec resolve([ExchangeMarketSnapshot.t()]) :: t() | nil
  def resolve(snapshots) do
    Enum.find_value(snapshots, &chaos_divine_rate/1)
  end

  defp chaos_divine_rate(%ExchangeMarketSnapshot{} = snapshot) do
    cond do
      chaos?(snapshot.currency_a) and divine?(snapshot.currency_b) ->
        averaged_rate(
          snapshot.currency_a,
          snapshot.currency_b,
          snapshot.lowest_ratio_a,
          snapshot.lowest_ratio_b,
          snapshot.highest_ratio_a,
          snapshot.highest_ratio_b
        )

      chaos?(snapshot.currency_b) and divine?(snapshot.currency_a) ->
        averaged_rate(
          snapshot.currency_b,
          snapshot.currency_a,
          snapshot.lowest_ratio_b,
          snapshot.lowest_ratio_a,
          snapshot.highest_ratio_b,
          snapshot.highest_ratio_a
        )

      true ->
        nil
    end
  end

  # Average of the hour's two rate extremes, expressed as Chaos received
  # per 1 Divine -- a simple point-estimate "fair value" for normalizing
  # profit figures, not a proposed trade (unlike UndercutQuote's buy/sell
  # prices, which deliberately pick the more/less favorable extreme).
  defp averaged_rate(
         chaos_currency,
         divine_currency,
         lowest_ratio_chaos,
         lowest_ratio_divine,
         highest_ratio_chaos,
         highest_ratio_divine
       ) do
    price_at_lowest = lowest_ratio_chaos / lowest_ratio_divine
    price_at_highest = highest_ratio_chaos / highest_ratio_divine

    %__MODULE__{
      chaos_currency: chaos_currency,
      divine_currency: divine_currency,
      chaos_per_divine: (price_at_lowest + price_at_highest) / 2.0
    }
  end

  @doc """
  Converts `quantity` of `currency` into its Chaos-equivalent using this
  rate -- the one shared place for a conversion each opportunity finder
  otherwise hand-rolls slightly differently for `profit` (always
  Chaos-denominated, per TECH_STACK.md's row design). `currency` is
  expected to already be this rate's own Chaos or Divine currency (every
  finder in this codebase only ever anchors a `start`/`profit` currency on
  one of those two), so there's no third-currency case to handle.
  """
  @spec to_chaos(t(), Currency.t(), number()) :: float()
  def to_chaos(%__MODULE__{} = rate, %Currency{} = currency, quantity) do
    if chaos?(currency, rate), do: quantity, else: quantity * rate.chaos_per_divine
  end

  defp chaos?(currency), do: currency.external_id == BaseCurrencyIds.chaos_external_id()
  defp divine?(currency), do: currency.external_id == BaseCurrencyIds.divine_external_id()
  defp chaos?(currency, rate), do: currency.external_id == rate.chaos_currency.external_id
end
