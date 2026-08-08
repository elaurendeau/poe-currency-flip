defmodule PoeFlipFinder.Currency do
  @moduledoc """
  A tradeable item on the Currency Exchange: a currency orb or a divination
  card. See docs/DATA_SOURCES.md § Item Icons for where external_id/icon_url
  come from.
  """

  @enforce_keys [:external_id, :display_name, :item_type]
  defstruct [:id, :external_id, :display_name, :icon_url, :item_type]

  @type item_type :: :currency | :divination_card

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          external_id: String.t(),
          display_name: String.t(),
          icon_url: String.t() | nil,
          item_type: item_type()
        }
end
