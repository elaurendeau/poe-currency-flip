defmodule PoeFlipFinder.VendorRecipeReferenceGateway do
  @moduledoc """
  Defined by the core for whatever it needs from vendor recipe data
  (docs/DATA_SOURCES.md § Vendor Sell Rates & Recipes).

  Returned recipes carry name-only placeholder `Currency` structs for
  `input_currency`/`output_currency` (no `id`/`external_id`) -- this
  gateway has no access to live Currency Exchange data to resolve those.
  Callers must match by `Currency.display_name` against currently-active
  market snapshots to get a fully-resolved Currency before using one in a
  FlipOpportunity, the same treatment `DivinationCardReferenceGateway`
  results get.
  """

  alias PoeFlipFinder.VendorRecipe

  @callback find_all() :: [VendorRecipe.t()]
end
