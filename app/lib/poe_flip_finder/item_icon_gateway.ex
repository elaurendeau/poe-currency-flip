defmodule PoeFlipFinder.ItemIconGateway do
  @moduledoc """
  Defined by the core for whatever it needs from GGG's Item Icons
  static-data (docs/DATA_SOURCES.md § Item Icons) -- resolving a
  never-before-seen Currency Exchange item path into a display name, icon
  URL, and item type. Not every path resolves (docs/DATA_SOURCES.md notes
  confirmed real examples with no catalog entry at all) -- `nil` is an
  expected outcome, not a failure.
  """

  alias PoeFlipFinder.Currency

  @callback lookup_item(external_id :: String.t()) :: Currency.t() | nil
end
