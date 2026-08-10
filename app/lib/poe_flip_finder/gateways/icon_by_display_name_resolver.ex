defmodule PoeFlipFinder.Gateways.IconByDisplayNameResolver do
  @moduledoc """
  A narrow, name-keyed lookup against the same bundled Item Icons catalog
  `GggItemIconGateway` uses (docs/DATA_SOURCES.md § Item Icons), for
  resolving an icon on a placeholder `Currency` that has no GGG item path
  to run through that gateway's path-based resolution at all --
  `HistoricalPricePattern` entries (docs/PRD.md § 7.14) only ever have a
  display name from poe-antiquary, never an `external_id`.

  Deliberately separate from `GggItemIconGateway`: that module's whole
  design is resolving a raw GGG item *path* to a name+icon, with several
  layers of fallback for path quirks the catalog doesn't cover directly.
  This is the much narrower inverse question -- "given a name I already
  have, is there a catalog entry whose `text` matches exactly" -- and
  inherits the same catalog gaps that module's moduledoc documents
  (Tattoos, Omens, and Runegrafts share one generic icon or an unrelated
  pre-rework name in the catalog; Cluster Jewels aren't in it at all,
  since they never trade on the Currency Exchange). Returning `nil` for
  those is correct, not a bug -- the UI already renders no icon for a
  `nil` `icon_url` (see `PoeFlipFinderWeb.FlipFinderLive.currency_icon/1`),
  same as any other genuinely-unresolvable item.
  """

  @catalog_resource_path "reference-data/item-icons-catalog.json"
  @persistent_term_key {__MODULE__, :icon_by_display_name}
  @image_host "https://www.pathofexile.com"

  @doc "The full icon URL for `display_name`, or `nil` if the catalog has no exact `text` match."
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
    |> Map.get("result", [])
    |> Enum.flat_map(& &1["entries"])
    |> Enum.filter(&(&1["image"] not in [nil, ""]))
    |> Map.new(&{&1["text"], @image_host <> &1["image"]})
  end
end
