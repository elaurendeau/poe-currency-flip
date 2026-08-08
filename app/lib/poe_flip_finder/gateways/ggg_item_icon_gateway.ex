defmodule PoeFlipFinder.Gateways.GggItemIconGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.ItemIconGateway`,
  reading GGG's public Item Icons static-data (docs/DATA_SOURCES.md §
  Item Icons) from a bundled resource rather than fetching it live --
  `www.pathofexile.com/api/trade/data/static` and its CDN mirror both
  return HTTP 403 from Render's IP (confirmed live 2026-08-06). Since this
  catalog is static, rarely-changing data, it's captured once into
  `priv/reference-data/item-icons-catalog.json` and refreshed manually.

  The match key against a Currency Exchange item path is **not** the
  catalog's `id` field (a short trade-UI slug unrelated to the metadata
  path) -- it's the filename tail of the `image` URL for most items, or a
  normalized comparison against `text` for divination cards (which have no
  `image` field at all). Both verified by direct testing 2026-08-06; see
  docs/DATA_SOURCES.md § Item Icons.

  **Exact basename matching only covers some groups.** Verified against a
  real hour of live Currency Exchange data 2026-08-07: GGG's own catalog
  drops a leading part of the real item path's basename for some items --
  every Essence entry's image basename omits the `CurrencyEssence` prefix
  (e.g. real path basename `CurrencyEssenceHatred5` vs. catalog basename
  `Hatred5`), and *The Maven's Writ* omits just `Currency`
  (`CurrencyMavenKey` vs. `MavenKey`) -- while common currencies like
  Chaos/Portal/Wisdom keep the full basename. There's no single prefix
  rule, so an exact-match miss falls back to the longest catalog basename
  that is a suffix of the real basename (`suffix_match/2`). This is a
  heuristic fallback, not a verified contract like the exact match above
  -- it resolved 79 previously-invisible items (mostly Essences, plus
  Maven/Uber-boss key fragments) with zero ambiguous matches in that
  sample, and `@min_suffix_match_length` guards against a short catalog
  basename coincidentally matching an unrelated item.

  The parsed catalog is cached in `:persistent_term` after first load --
  it's ~200KB of effectively-immutable data read very frequently (once per
  never-before-seen item during ingestion), the textbook fit for
  `:persistent_term` over re-parsing on every call or a GenServer round trip.
  """

  @behaviour PoeFlipFinder.ItemIconGateway

  alias PoeFlipFinder.Currency

  @divination_card_prefix "DivinationCard"
  @catalog_resource_path "reference-data/item-icons-catalog.json"
  @min_suffix_match_length 4
  @persistent_term_key {__MODULE__, :catalog}

  @type catalog :: %{by_image_basename: map(), cards_by_canonical_name: map()}

  @impl true
  def lookup_item(external_id), do: lookup_item(external_id, ensure_catalog_loaded())

  @doc """
  Pure lookup against an already-normalized catalog -- what contract tests
  exercise directly, feeding a fixture-derived catalog rather than the real
  bundled file.
  """
  @spec lookup_item(String.t(), catalog()) :: Currency.t() | nil
  def lookup_item(external_id, catalog) do
    basename = basename_of(external_id)

    if String.starts_with?(basename, @divination_card_prefix) do
      lookup_card(external_id, basename, catalog.cards_by_canonical_name)
    else
      lookup_currency(external_id, basename, catalog.by_image_basename)
    end
  end

  defp lookup_currency(external_id, basename, by_image_basename) do
    case Map.get(by_image_basename, basename) || suffix_match(basename, by_image_basename) do
      nil ->
        nil

      entry ->
        %Currency{
          id: nil,
          external_id: external_id,
          display_name: entry["text"],
          icon_url: to_absolute_icon_url(entry["image"]),
          category: entry["__category"]
        }
    end
  end

  # Tries progressively shorter suffixes of the real basename, so the first
  # hit is the longest (most specific, least collision-prone) catalog
  # basename that matches.
  defp suffix_match(basename, by_image_basename) do
    max_start = String.length(basename) - @min_suffix_match_length

    if max_start < 1 do
      nil
    else
      Enum.find_value(1..max_start, fn start ->
        Map.get(by_image_basename, String.slice(basename, start..-1//1))
      end)
    end
  end

  defp lookup_card(external_id, basename, cards_by_canonical_name) do
    card_name = String.slice(basename, String.length(@divination_card_prefix)..-1//1)

    case Map.get(cards_by_canonical_name, canonicalize(card_name)) do
      nil ->
        nil

      entry ->
        %Currency{
          id: nil,
          external_id: external_id,
          display_name: entry["text"],
          icon_url: nil,
          category: entry["__category"]
        }
    end
  end

  defp ensure_catalog_loaded do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        catalog = normalize(Jason.decode!(read_bundled_catalog()))
        :persistent_term.put(@persistent_term_key, catalog)
        catalog

      catalog ->
        catalog
    end
  end

  defp read_bundled_catalog do
    :poe_flip_finder
    |> Application.app_dir("priv")
    |> Path.join(@catalog_resource_path)
    |> File.read!()
  end

  @doc "Exposed so contract tests can exercise parsing without reading the bundled file."
  @spec normalize(map()) :: catalog()
  def normalize(raw_catalog) do
    Enum.reduce(
      raw_catalog["result"],
      %{by_image_basename: %{}, cards_by_canonical_name: %{}},
      fn group, acc ->
        Enum.reduce(group["entries"], acc, &add_entry(&2, group, &1))
      end
    )
  end

  defp add_entry(acc, group, entry) do
    entry = Map.put(entry, "__category", category_for_group(group["id"]))

    case entry["image"] do
      nil -> maybe_add_card(acc, group, entry)
      image -> put_in(acc, [:by_image_basename, basename_of_image(image)], entry)
    end
  end

  defp maybe_add_card(acc, %{"id" => "Cards"}, entry),
    do: put_in(acc, [:cards_by_canonical_name, canonicalize(entry["text"])], entry)

  defp maybe_add_card(acc, _group, _entry), do: acc

  # Maps the catalog's own raw group ids (docs/DATA_SOURCES.md § Item Icons)
  # to PoeFlipFinder.Currency.category() atoms. An id this map doesn't know
  # about (a future catalog refresh introducing a new group) falls back to
  # :misc rather than crashing currency resolution -- the same "never crash
  # on unrecognized external data" instinct as this codebase's other
  # defensive-fallback parsing (e.g. flip_finder_live.ex's
  # parse_enabled_techniques/2).
  @category_by_group_id %{
    "Cards" => :cards,
    "Fragments" => :fragments,
    "Ancestor" => :ancestor,
    "Essences" => :essences,
    "Currency" => :currency,
    "Beasts" => :beasts,
    "MapKey" => :map_key,
    "Heist" => :heist,
    "Runegrafts" => :runegrafts,
    "Delve" => :delve,
    "Sanctum" => :sanctum,
    "MapsUnique" => :maps_unique,
    "DeliriumOrbs" => :delirium_orbs,
    "Oils" => :oils,
    "Catalysts" => :catalysts,
    "Ducats" => :ducats,
    "MapsSpecial" => :maps_special,
    "AllflameEmbers" => :allflame_embers,
    "Keepers" => :keepers,
    "EnshroudingCrystals" => :enshrouding_crystals,
    "Legacy" => :legacy,
    "Expedition" => :expedition,
    "Misc" => :misc
  }

  defp category_for_group(group_id), do: Map.get(@category_by_group_id, group_id, :misc)

  defp basename_of(external_id), do: external_id |> String.split("/") |> List.last()

  defp basename_of_image(image) do
    filename = image |> String.split("/") |> List.last()

    if String.ends_with?(filename, ".png"),
      do: String.replace_suffix(filename, ".png", ""),
      else: filename
  end

  defp canonicalize(text), do: text |> String.replace(" ", "") |> String.downcase()

  defp to_absolute_icon_url(relative_path), do: "https://www.pathofexile.com" <> relative_path
end
