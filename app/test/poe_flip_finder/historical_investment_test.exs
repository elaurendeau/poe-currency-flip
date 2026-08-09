defmodule PoeFlipFinder.HistoricalInvestmentTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.HistoricalInvestment
  alias PoeFlipFinder.HistoricalPricePattern
  alias PoeFlipFinder.HistoricalPricePattern.LeagueObservation

  # Use-Case Discovery per docs/ELIXIR_TEST_MANIFESTO.md, traced to
  # docs/PRD.md § 7.14: golden-path projection math, the two interpolated
  # (modeled) horizons vs. the two observed ones, the "not enough for 1"
  # boundary, and a league whose day-1 price actually dropped below day-0
  # (Orb of Annulment's Ancestor observation) -- interpolation must not
  # assume growth is always positive.

  defp pattern(observations) do
    %HistoricalPricePattern{
      currency: %PoeFlipFinder.Currency{
        id: nil,
        external_id: nil,
        display_name: "Test Currency",
        icon_url: nil,
        category: :currency
      },
      league_observations: observations
    }
  end

  defp observation(league, day0, day1, day2) do
    %LeagueObservation{league: league, day0_chaos: day0, day1_chaos: day1, day2_chaos: day2}
  end

  describe "project_pattern/2" do
    test "computes units affordable and all four horizon values on the golden path" do
      # Real Necropolis Exalted Orb numbers, per priv/reference-data/
      # historical-investment-patterns.json.
      p = pattern([observation("Necropolis", 3.0, 9.0, 10.74)])

      [projected] = HistoricalInvestment.project_pattern(p, 40)

      assert projected.league == "Necropolis"
      assert projected.day0_chaos == 3.0
      assert projected.units == 13
      assert projected.affordable == true

      by_hours = Map.new(projected.projections, &{&1.hours, &1})
      assert_in_delta by_hours[6].value_chaos, 58.5, 0.001
      assert_in_delta by_hours[12].value_chaos, 78.0, 0.001
      assert_in_delta by_hours[24].value_chaos, 117.0, 0.001
      assert_in_delta by_hours[48].value_chaos, 139.62, 0.001
    end

    test "flags 6h/12h as modeled and 24h/48h as observed" do
      p = pattern([observation("Necropolis", 3.0, 9.0, 10.74)])
      [projected] = HistoricalInvestment.project_pattern(p, 40)

      by_hours = Map.new(projected.projections, &{&1.hours, &1})
      assert by_hours[6].modeled == true
      assert by_hours[12].modeled == true
      assert by_hours[24].modeled == false
      assert by_hours[48].modeled == false
    end

    test "an amount that can't buy even 1 unit yields no projections, not a misleading 0c" do
      p = pattern([observation("Necropolis", 61.6, 97.2, 137.0)])

      [projected] = HistoricalInvestment.project_pattern(p, 40)

      assert projected.units == 0
      assert projected.affordable == false
      assert projected.projections == []
    end

    test "interpolates a genuine day-0-to-day-1 price drop, not just growth" do
      # Real Ancestor Orb of Annulment observation: day-0 was 8.8c, day-1
      # dropped to 6.0c before day-2 recovered to 10.0c.
      p = pattern([observation("Ancestor", 8.8, 6.0, 10.0)])

      [projected] = HistoricalInvestment.project_pattern(p, 40)
      assert projected.units == 4

      by_hours = Map.new(projected.projections, &{&1.hours, &1})
      # 6h/12h sit between the day-0 and day-1 prices, which here means
      # below the day-0 baseline, not above it.
      assert_in_delta by_hours[6].value_chaos, 4 * 8.1, 0.001
      assert_in_delta by_hours[12].value_chaos, 4 * 7.4, 0.001
      assert_in_delta by_hours[24].value_chaos, 4 * 6.0, 0.001
      assert_in_delta by_hours[48].value_chaos, 4 * 10.0, 0.001
    end

    test "projects every league observation independently, not just the first" do
      p =
        pattern([
          observation("Necropolis", 3.0, 9.0, 10.74),
          observation("Affliction", 4.0, 5.0, 9.0)
        ])

      projected = HistoricalInvestment.project_pattern(p, 40)

      assert Enum.map(projected, & &1.league) == ["Necropolis", "Affliction"]
      assert Enum.map(projected, & &1.units) == [13, 10]
    end
  end

  describe "compute_candidates/1" do
    test "reads the real bundled reference data and projects every candidate" do
      candidates = HistoricalInvestment.compute_candidates(40)

      assert length(candidates) == 5

      exalted = Enum.find(candidates, &(&1.pattern.currency.display_name == "Exalted Orb"))
      assert length(exalted.league_projections) == 2

      awakeners = Enum.find(candidates, &(&1.pattern.currency.display_name == "Awakener's Orb"))
      assert Enum.all?(awakeners.league_projections, &(&1.affordable == false))
    end
  end
end
