defmodule PoeFlipFinder.VendorRecipe do
  @moduledoc """
  A vendor sell-rate or multi-item recipe, manually captured from the PoE Wiki
  per docs/DATA_SOURCES.md. A plain sell rate is just input_quantity = 1.
  """

  alias PoeFlipFinder.Currency

  @enforce_keys [:input_currency, :input_quantity, :output_currency, :output_quantity]
  defstruct [:id, :input_currency, :input_quantity, :output_currency, :output_quantity]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          input_currency: Currency.t(),
          input_quantity: pos_integer(),
          output_currency: Currency.t(),
          output_quantity: pos_integer()
        }
end
