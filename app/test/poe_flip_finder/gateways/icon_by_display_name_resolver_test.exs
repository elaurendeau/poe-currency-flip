defmodule PoeFlipFinder.Gateways.IconByDisplayNameResolverTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.IconByDisplayNameResolver

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: the real bundled
  # item-icons-catalog.json in, an asserted resolved (or correctly
  # unresolved) icon URL out.

  test "resolves a real currency name to its full, absolute icon URL" do
    assert IconByDisplayNameResolver.resolve("Exalted Orb") ==
             "https://www.pathofexile.com/gen/image/WzI1LDE0LHsiZiI6IjJESXRlbXMvQ3VycmVuY3kvQ3VycmVuY3lBZGRNb2RUb1JhcmUiLCJzY2FsZSI6MX1d/33f2656aea/CurrencyAddModToRare.png"
  end

  test "resolves Divine Orb too, not just Exalted (not a one-item coincidence)" do
    assert IconByDisplayNameResolver.resolve("Divine Orb") =~ "CurrencyModValues.png"
  end

  test "is nil for a name with no exact catalog match, e.g. a Cluster Jewel" do
    assert IconByDisplayNameResolver.resolve(
             "Medium Cluster Jewel (8 passives, Lv50): 12% increased Fire Damage"
           ) ==
             nil
  end

  test "is nil for a name that simply doesn't exist anywhere" do
    assert IconByDisplayNameResolver.resolve("Definitely Not A Real Item Name") == nil
  end
end
