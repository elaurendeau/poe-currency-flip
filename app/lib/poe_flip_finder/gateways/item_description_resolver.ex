defmodule PoeFlipFinder.Gateways.ItemDescriptionResolver do
  @moduledoc """
  A narrow, name-keyed lookup against a bundled catalog of real item
  descriptions captured from the PoE Wiki's Cargo query API
  (docs/DATA_SOURCES.md § Item Descriptions) -- backs the hover tooltip
  shown next to a currency's name across every tab, since a name alone
  (e.g. "Runegraft of the Witchmark") often doesn't say what the item
  actually does.

  Same shape and rationale as `IconByDisplayNameResolver`: a flat
  name -> value lookup, persistent_term-cached after first load. `nil`
  for a name the catalog has no entry for is correct, not a bug -- the
  catalog only covers the Currency-category items and the categories
  Historical Investment (docs/PRD.md § 7.14) curates, not every item
  GGG's Item Icons catalog knows about. Callers fall back to a plain
  "Unknown" tooltip on `nil` rather than hiding the item or fabricating
  a description (see `HistoricalInvestmentPresenter.format_description/1`).
  """

  @catalog_resource_path "reference-data/item-descriptions-catalog.json"
  @persistent_term_key {__MODULE__, :description_by_display_name}

  @doc "The real captured description for `display_name`, or `nil` if the catalog has no entry."
  @spec resolve(String.t()) :: String.t() | nil
  def resolve(display_name), do: Map.get(index(), display_name)

  defp index do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        built = build_index()
        :persistent_term.put(@persistent_term_key, built)
        built

      built ->
        built
    end
  end

  defp build_index do
    :poe_flip_finder
    |> Application.app_dir("priv")
    |> Path.join(@catalog_resource_path)
    |> File.read!()
    |> Jason.decode!()
  end
end
