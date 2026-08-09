defmodule PoeFlipFinder.Currency do
  @moduledoc """
  A tradeable item on the Currency Exchange: a currency orb, a divination
  card, or any other item category GGG's own Item Icons catalog groups
  items into. See docs/DATA_SOURCES.md § Item Icons for where
  external_id/icon_url come from, and where this exact set of 23 groups
  (`Currency`, `Fragments`, `Cards`, `Oils`, ...) is sourced.
  """

  @enforce_keys [:external_id, :display_name, :category]
  defstruct [:id, :external_id, :display_name, :icon_url, :category]

  @type category ::
          :cards
          | :fragments
          | :ancestor
          | :essences
          | :currency
          | :beasts
          | :map_key
          | :heist
          | :runegrafts
          | :delve
          | :sanctum
          | :maps_unique
          | :delirium_orbs
          | :oils
          | :catalysts
          | :ducats
          | :maps_special
          | :allflame_embers
          | :keepers
          | :enshrouding_crystals
          | :legacy
          | :expedition
          | :misc
          # Historical-only category, docs/PRD.md § 7.14: real poe-antiquary
          # data exists, but nothing here ever trades on GGG's Currency
          # Exchange (roll-dependent, not fungible) -- never appears on a
          # live-resolved Currency, only on HistoricalPricePattern's
          # placeholder one, so it's deliberately not in the `currency`
          # table's DB check constraint.
          | :cluster_jewels

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          external_id: String.t(),
          display_name: String.t(),
          icon_url: String.t() | nil,
          category: category()
        }
end
