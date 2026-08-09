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

    assert length(patterns) == 5

    exalted = Enum.find(patterns, &(&1.currency.display_name == "Exalted Orb"))
    assert exalted.currency.external_id == nil
    assert exalted.currency.category == :currency
    assert length(exalted.league_observations) == 2

    necropolis = Enum.find(exalted.league_observations, &(&1.league == "Necropolis"))
    assert necropolis.day0_chaos == 3.0
    assert necropolis.day1_chaos == 9.0
    assert necropolis.day2_chaos == 10.74
  end

  test "captures Ancestor's Orb of Annulment dip, not just leagues that rose" do
    patterns = BundledHistoricalPatternReferenceGateway.find_all()
    annulment = Enum.find(patterns, &(&1.currency.display_name == "Orb of Annulment"))

    ancestor = Enum.find(annulment.league_observations, &(&1.league == "Ancestor"))
    assert ancestor.day0_chaos == 8.8
    assert ancestor.day1_chaos == 6.0
    assert ancestor.day1_chaos < ancestor.day0_chaos
  end

  test "normalize/1 maps raw JSON fields onto HistoricalPricePattern" do
    raw = [
      %{
        "currencyName" => "Chromatic Orb",
        "leagueObservations" => [
          %{"league" => "Necropolis", "day0Chaos" => 0.09, "day1Chaos" => 0.17, "day2Chaos" => 0.17}
        ]
      }
    ]

    [pattern] = BundledHistoricalPatternReferenceGateway.normalize(raw)

    assert pattern.currency.display_name == "Chromatic Orb"
    assert pattern.currency.category == :currency
    [observation] = pattern.league_observations
    assert observation.league == "Necropolis"
    assert observation.day0_chaos == 0.09
  end
end
