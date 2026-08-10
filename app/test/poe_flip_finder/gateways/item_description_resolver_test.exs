defmodule PoeFlipFinder.Gateways.ItemDescriptionResolverTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.ItemDescriptionResolver

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: the real bundled
  # item-descriptions-catalog.json in, an asserted resolved (or correctly
  # unresolved) description out.

  test "resolves a real currency name to its real captured mod/effect text" do
    assert ItemDescriptionResolver.resolve("Chaos Orb") ==
             "Reforges a rare item with new random modifiers"
  end

  test "resolves a base currency backfilled specifically for the live-currency tabs" do
    # poe.ninja's historical archive never carries this item (see
    # docs/DATA_SOURCES.md), so it was captured in a separate, smaller
    # batch just for Grand Exchange/Vendor Flip's live tooltip coverage.
    assert ItemDescriptionResolver.resolve("Divine Orb") ==
             "Randomises the values of the random modifiers on an item"
  end

  test "is nil for a name with no captured description, e.g. a Beast" do
    assert ItemDescriptionResolver.resolve("Definitely Not A Real Item Name") == nil
  end
end
