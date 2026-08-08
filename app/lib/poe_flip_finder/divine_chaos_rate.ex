defmodule PoeFlipFinder.DivineChaosRate do
  @moduledoc """
  The Chaos<->Divine exchange rate for a league's active generation,
  averaged from the hour's two rate extremes -- a point-estimate "fair
  value" for normalizing profit figures, not a proposed trade. Used to
  convert Divine-denominated amounts into Chaos (Exchange Spread) and to
  benchmark the direct rate a Bulk Buy opportunity must beat.
  """

  alias PoeFlipFinder.Currency

  @enforce_keys [:chaos_currency, :divine_currency, :chaos_per_divine]
  defstruct [:chaos_currency, :divine_currency, :chaos_per_divine]

  @type t :: %__MODULE__{
          chaos_currency: Currency.t(),
          divine_currency: Currency.t(),
          chaos_per_divine: float()
        }
end
