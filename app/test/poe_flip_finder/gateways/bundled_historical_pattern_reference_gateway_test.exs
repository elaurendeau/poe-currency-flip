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

    exalted = Enum.find(patterns, &(&1.currency.display_name == "Exalted Orb"))
    assert exalted.currency.external_id == nil
    assert exalted.currency.category == :currency
    assert length(exalted.league_observations) == 4

    necropolis = Enum.find(exalted.league_observations, &(&1.league == "Necropolis"))
    day0 = Enum.find(necropolis.day_prices, &(&1.day == 0))
    day1 = Enum.find(necropolis.day_prices, &(&1.day == 1))
    assert day0.chaos == 3.0
    assert day1.chaos == 9.0
  end

  test "loads the historical-only Cluster Jewel category with a category not in the live DB enum" do
    patterns = BundledHistoricalPatternReferenceGateway.find_all()
    jewel = Enum.find(patterns, &(&1.currency.display_name =~ "Cluster Jewel"))

    assert jewel.currency.category == :cluster_jewels
  end

  test "captures a real league observation that doesn't start at day 0 (Farrul in Affliction)" do
    patterns = BundledHistoricalPatternReferenceGateway.find_all()
    farrul = Enum.find(patterns, &(&1.currency.display_name == "Farrul, First of the Plains"))
    affliction = Enum.find(farrul.league_observations, &(&1.league == "Affliction"))

    refute Enum.any?(affliction.day_prices, &(&1.day == 0))
    assert Enum.any?(affliction.day_prices, &(&1.day == 5))
  end

  test "normalize/1 maps raw JSON fields onto HistoricalPricePattern" do
    raw = [
      %{
        "currencyName" => "Chromatic Orb",
        "category" => "currency",
        "leagueObservations" => [
          %{"league" => "Necropolis", "days" => [%{"day" => 0, "chaos" => 0.09}, %{"day" => 1, "chaos" => 0.17}]}
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
end
