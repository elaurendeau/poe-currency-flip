defmodule PoeFlipFinder.Gateways.BundledVendorRecipeReferenceGateway do
  @moduledoc """
  The imperative-shell implementation of
  `PoeFlipFinder.VendorRecipeReferenceGateway`, reading manually-captured
  PoE Wiki vendor recipe data (docs/DATA_SOURCES.md § Vendor Sell Rates &
  Recipes) from a bundled resource -- same treatment as
  `BundledDivinationCardReferenceGateway`, since neither source has a live
  API to fetch from.

  The `input_currency`/`output_currency` fields of returned `VendorRecipe`
  entities are name-only placeholders (no `id`, `external_id`, or
  `icon_url`) -- this gateway has no access to live Currency Exchange data
  to resolve those against. Callers must match by `Currency.display_name`
  against currently-active market snapshots to get a fully-resolved
  Currency before using one in a FlipOpportunity.

  The parsed list is cached in `:persistent_term` after first load, same
  rationale as `BundledDivinationCardReferenceGateway`: small,
  effectively-immutable data read on every flip-opportunities computation.
  """

  @behaviour PoeFlipFinder.VendorRecipeReferenceGateway

  alias PoeFlipFinder.{Currency, VendorRecipe}

  @catalog_resource_path "reference-data/vendor-recipes.json"
  @persistent_term_key {__MODULE__, :vendor_recipes}

  @impl true
  def find_all, do: ensure_loaded()

  defp ensure_loaded do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        recipes = normalize(Jason.decode!(read_bundled_catalog()))
        :persistent_term.put(@persistent_term_key, recipes)
        recipes

      recipes ->
        recipes
    end
  end

  defp read_bundled_catalog do
    :poe_flip_finder
    |> Application.app_dir("priv")
    |> Path.join(@catalog_resource_path)
    |> File.read!()
  end

  @doc "Exposed so contract tests can exercise parsing without reading the bundled file."
  @spec normalize([map()]) :: [VendorRecipe.t()]
  def normalize(raw_entries), do: Enum.map(raw_entries, &to_entity/1)

  defp to_entity(entry) do
    %VendorRecipe{
      input_currency: placeholder_currency(entry["inputCurrencyName"]),
      input_quantity: entry["inputQuantity"],
      output_currency: placeholder_currency(entry["outputCurrencyName"]),
      output_quantity: entry["outputQuantity"]
    }
  end

  defp placeholder_currency(name) do
    %Currency{id: nil, external_id: nil, display_name: name, icon_url: nil, category: :currency}
  end
end
