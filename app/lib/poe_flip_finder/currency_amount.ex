defmodule PoeFlipFinder.CurrencyAmount do
  @moduledoc "A quantity of a specific currency, e.g. \"86 Orb of Transmutation.\""

  alias PoeFlipFinder.Currency

  @enforce_keys [:currency, :quantity]
  defstruct [:currency, :quantity]

  @type t :: %__MODULE__{currency: Currency.t(), quantity: float()}
end
