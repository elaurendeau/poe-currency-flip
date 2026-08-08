defmodule PoeFlipFinder.Gateways.GggItemIconGatewayTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.GggItemIconGateway

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: a saved real Item
  # Icons response in, an asserted resolved (or unresolved) Currency out.
  # Most tests build a catalog from the fixture via normalize/1 and call
  # the pure lookup_item/2, mirroring the Java version's
  # normalize-then-lookup pattern without needing to seed global state.

  test "loads the real bundled catalog resource without needing normalize/1 first" do
    # Regression test: this gateway reads a bundled priv/ file rather than
    # fetching live (both www.pathofexile.com and its CDN mirror return 403
    # from production -- docs/DATA_SOURCES.md § Item Icons). Deliberately
    # calls the single-arg lookup_item/1, which goes through the real
    # ensure_catalog_loaded/0 path, so this only passes if
    # priv/reference-data/item-icons-catalog.json is present and parses.
    result = GggItemIconGateway.lookup_item("Metadata/Items/Currency/CurrencyPortal")

    assert result.display_name == "Portal Scroll"
  end

  test "resolves a currency via the image filename basename, not the id field" do
    catalog = GggItemIconGateway.normalize(fixture())

    result = GggItemIconGateway.lookup_item("Metadata/Items/Currency/CurrencyPortal", catalog)

    assert result.display_name == "Portal Scroll"
    assert result.category == :currency
    assert String.starts_with?(result.icon_url, "https://www.pathofexile.com/gen/image/")
    assert result.external_id == "Metadata/Items/Currency/CurrencyPortal"
  end

  test "resolves a divination card via normalized text comparison, with no icon URL" do
    catalog = GggItemIconGateway.normalize(fixture())

    result =
      GggItemIconGateway.lookup_item(
        "Metadata/Items/DivinationCards/DivinationCardTheApothecary",
        catalog
      )

    assert result.display_name == "The Apothecary"
    assert result.category == :cards
    assert result.icon_url == nil
  end

  test "returns nil for an item not in the catalog" do
    catalog = GggItemIconGateway.normalize(fixture())

    # Verified real example (docs/DATA_SOURCES.md § Item Icons): this item
    # genuinely has no catalog entry in any group.
    result =
      GggItemIconGateway.lookup_item(
        "Metadata/Items/Currency/CurrencyBreachUpgradeUniqueGeneral",
        catalog
      )

    assert result == nil
  end

  test "resolves an Essence by falling back to a suffix match" do
    catalog = GggItemIconGateway.normalize(fixture())

    # Real example verified against live Currency Exchange data
    # 2026-08-07: the catalog's image basename for essences omits the
    # "CurrencyEssence" prefix that the real item path keeps, so the
    # exact-match lookup misses and must fall back to a suffix match.
    result =
      GggItemIconGateway.lookup_item("Metadata/Items/Currency/CurrencyEssenceHatred5", catalog)

    assert result.display_name == "Screaming Essence of Hatred"
    assert result.category == :essences
  end

  test "resolves Maven's Writ by falling back to a suffix match" do
    catalog = GggItemIconGateway.normalize(fixture())

    # Real example verified 2026-08-07: catalog basename "MavenKey" vs.
    # real basename "CurrencyMavenKey" -- only the "Currency" prefix is
    # dropped here, unlike the longer prefix essences drop.
    result =
      GggItemIconGateway.lookup_item("Metadata/Items/MapFragments/CurrencyMavenKey", catalog)

    assert result.display_name == "The Maven's Writ"
  end

  test "does not suffix-match when the only candidate is shorter than the minimum length" do
    catalog = GggItemIconGateway.normalize(fixture())

    # The fixture's "Misc" group has a 3-character basename ("Tal") that
    # this real path's basename ends in -- proves the minimum suffix
    # length actually suppresses a match that would otherwise succeed, not
    # just that unrelated items stay unmatched.
    result = GggItemIconGateway.lookup_item("Metadata/Items/Currency/CurrencyFooBarTal", catalog)

    assert result == nil
  end

  defp fixture do
    Path.join([__DIR__, "..", "..", "fixtures", "ggg_item_icons", "catalog.json"])
    |> File.read!()
    |> Jason.decode!()
  end
end
