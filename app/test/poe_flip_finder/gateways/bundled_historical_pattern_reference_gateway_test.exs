defmodule PoeFlipFinder.Gateways.BundledHistoricalPatternReferenceGatewayTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.BundledHistoricalPatternReferenceGateway

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: the real bundled
  # historical-investment-patterns.json in, asserted normalized
  # HistoricalPricePattern structs out.

  test "loads the real bundled catalog resource without needing normalize/1 first" do
    # Deliberately calls the zero-arg find_all/0, which goes through the
    # real ensure_loaded/0 path -- only passes if
    # priv/reference-data/historical-investment-patterns.json is present
    # and parses.
    patterns = BundledHistoricalPatternReferenceGateway.find_all()

    assert length(patterns) >= 15

    ancient_orb = Enum.find(patterns, &(&1.currency.display_name == "Ancient Orb"))
    assert ancient_orb.currency.external_id == nil
    assert ancient_orb.currency.category == :currency
    # Ancestors (most recent) + Mirage (older, deeper fallback) -- see
    # docs/DATA_SOURCES.md's "past 2 leagues" rationale.
    assert length(ancient_orb.league_observations) == 2
    assert ancient_orb.currency.icon_url =~ "AncientOrb.png"
    # A real hover description, resolved onto the placeholder Currency
    # (not the pattern itself) by the shared ItemDescriptionResolver --
    # same catalog every other Currency-hydrating gateway reads from.
    assert ancient_orb.currency.description ==
             "Reforges a unique equipment as another of the same item class"

    ancestors = Enum.find(ancient_orb.league_observations, &(&1.league == "Ancestors"))
    day0 = Enum.find(ancestors.day_prices, &(&1.day == 0))
    day1 = Enum.find(ancestors.day_prices, &(&1.day == 1))
    assert day0.chaos == 2.45
    assert day1.chaos == 3.51
  end

  test "loads the historical-only Cluster Jewel category with a category not in the live DB enum" do
    patterns = BundledHistoricalPatternReferenceGateway.find_all()
    jewel = Enum.find(patterns, &(&1.currency.display_name =~ "Cluster Jewel"))

    assert jewel.currency.category == :cluster_jewels
    # Cluster Jewels never trade on the Currency Exchange, so GGG's own
    # Item Icons catalog has no entry for them at all -- nil is the
    # correct, honest result here, not a resolution bug.
    assert jewel.currency.icon_url == nil
    # Cluster Jewels have no wiki page of their own -- the notable mod
    # text after ": " in the display name IS the real description, so it's
    # derived from the name rather than looked up.
    [_prefix, notable] = String.split(jewel.currency.display_name, ": ", parts: 2)
    assert jewel.currency.description == notable
  end

  test "captures a real league observation that doesn't start at day 0 (Flesh of Xesht in Mirage)" do
    patterns = BundledHistoricalPatternReferenceGateway.find_all()
    flesh = Enum.find(patterns, &(&1.currency.display_name == "Flesh of Xesht"))
    mirage = Enum.find(flesh.league_observations, &(&1.league == "Mirage"))

    # Real poe.ninja data: this item's Mirage series has no real listing
    # until day 31 (it presumably wasn't tradeable/priced before then) --
    # not every league observation for every item starts at day 0.
    refute Enum.any?(mirage.day_prices, &(&1.day == 0))
    assert Enum.any?(mirage.day_prices, &(&1.day == 31))
  end

  test "normalize/1 maps raw JSON fields onto HistoricalPricePattern" do
    raw = [
      %{
        "currencyName" => "Chromatic Orb",
        "category" => "currency",
        "leagueObservations" => [
          %{
            "league" => "Necropolis",
            "days" => [%{"day" => 0, "chaos" => 0.09}, %{"day" => 1, "chaos" => 0.17}]
          }
        ]
      }
    ]

    [pattern] = BundledHistoricalPatternReferenceGateway.normalize(raw)

    assert pattern.currency.display_name == "Chromatic Orb"
    assert pattern.currency.category == :currency
    [observation] = pattern.league_observations
    assert observation.league == "Necropolis"
    [day0, day1] = observation.day_prices
    assert day0.day == 0
    assert day0.chaos == 0.09
    assert day1.day == 1
    assert day1.chaos == 0.17
  end

  test "normalize/1 maps every real category string used in the bundled data, not just :currency" do
    # Regression test: category parsing originally used
    # String.to_existing_atom/1, which raised a real ArgumentError ("not
    # an already existing atom") when this exact test file ran in
    # isolation -- whether e.g. :cards was already interned depended on
    # which other modules happened to load first in the run. An explicit
    # map fixes it; this asserts every category the real bundled JSON
    # actually uses round-trips correctly regardless of load order.
    for category <- ~w(currency cards essences beasts ancestor oils cluster_jewels runegrafts) do
      raw = [%{"currencyName" => "Test Item", "category" => category, "leagueObservations" => []}]
      [pattern] = BundledHistoricalPatternReferenceGateway.normalize(raw)
      assert pattern.currency.category == String.to_atom(category)
    end
  end

  test "normalize/1 derives a Cluster Jewel's description from its own name, not a wiki lookup" do
    raw = [
      %{
        "currencyName" =>
          "Large Cluster Jewel (8 passives, Lv75): 10% increased Elemental Damage",
        "category" => "cluster_jewels",
        "leagueObservations" => []
      }
    ]

    [pattern] = BundledHistoricalPatternReferenceGateway.normalize(raw)

    assert pattern.currency.description == "10% increased Elemental Damage"
  end

  test "normalize/1 falls back to nil description when a Cluster Jewel name has no ': ' separator" do
    raw = [
      %{
        "currencyName" => "Cluster Jewel",
        "category" => "cluster_jewels",
        "leagueObservations" => []
      }
    ]

    [pattern] = BundledHistoricalPatternReferenceGateway.normalize(raw)

    assert pattern.currency.description == nil
  end

  test "normalize/1 raises a specific, loud error on an unrecognized category" do
    raw = [
      %{
        "currencyName" => "Mystery Item",
        "category" => "not_a_real_category",
        "leagueObservations" => []
      }
    ]

    assert_raise ArgumentError, ~r/unrecognized Historical Investment category/, fn ->
      BundledHistoricalPatternReferenceGateway.normalize(raw)
    end
  end
end
