defmodule PoeFlipFinder.HistoricalInvestment do
  @moduledoc """
  Computes Historical Investment candidates and their projected value at a
  given Chaos investment amount, per docs/PRD.md § 7.14 Feature N.

  Not scoped to the currently-selected league (docs/PRD.md § 7.4 Feature
  D) -- `list_patterns/0` returns the full curated past-league sample
  regardless, since this feature is forward-looking evidence for whichever
  league is about to start, not history for a league that already has its
  own live data.
  """

  alias PoeFlipFinder.HistoricalPricePattern
  alias PoeFlipFinder.HistoricalPricePattern.LeagueObservation

  # 24h/48h read the archive's real observed day-1/day-2 snapshots. 6h/12h
  # have no genuine sub-day resolution in the source data (docs/
  # DATA_SOURCES.md § Historical League Price Archive) and are linearly
  # interpolated between day-0 and day-1 instead -- callers must treat
  # those two as modeled, not observed (see `modeled` on each projection).
  @horizons_hours [6, 12, 24, 48]

  @type projection :: %{hours: pos_integer(), modeled: boolean(), value_chaos: float()}

  @type league_projection :: %{
          league: String.t(),
          day0_chaos: float(),
          units: non_neg_integer(),
          affordable: boolean(),
          projections: [projection()]
        }

  @type candidate :: %{
          pattern: HistoricalPricePattern.t(),
          league_projections: [league_projection()]
        }

  @spec list_patterns() :: [HistoricalPricePattern.t()]
  def list_patterns, do: historical_pattern_reference_gateway().find_all()

  @spec compute_candidates(number()) :: [candidate()]
  def compute_candidates(investment_amount) when is_number(investment_amount) do
    Enum.map(list_patterns(), fn pattern ->
      %{pattern: pattern, league_projections: project_pattern(pattern, investment_amount)}
    end)
  end

  @spec project_pattern(HistoricalPricePattern.t(), number()) :: [league_projection()]
  def project_pattern(%HistoricalPricePattern{} = pattern, investment_amount)
      when is_number(investment_amount) and investment_amount > 0 do
    Enum.map(pattern.league_observations, &project_observation(&1, investment_amount))
  end

  defp project_observation(%LeagueObservation{} = observation, investment_amount) do
    units = trunc(investment_amount / observation.day0_chaos)

    %{
      league: observation.league,
      day0_chaos: observation.day0_chaos,
      units: units,
      affordable: units > 0,
      # A `units == 0` row (the entered amount can't buy even one) carries
      # no projections at all -- docs/PRD.md § 7.14 requires an explicit
      # "not enough for 1" state, never a misleadingly-precise 0c figure
      # that a `units * price` computation would otherwise still produce.
      projections: if(units > 0, do: Enum.map(@horizons_hours, &build_projection(&1, observation, units)), else: [])
    }
  end

  defp build_projection(hours, observation, units) do
    %{
      hours: hours,
      modeled: hours in [6, 12],
      value_chaos: units * price_at_horizon(hours, observation)
    }
  end

  defp price_at_horizon(6, observation), do: interpolate(observation, 0.25)
  defp price_at_horizon(12, observation), do: interpolate(observation, 0.5)
  defp price_at_horizon(24, observation), do: observation.day1_chaos
  defp price_at_horizon(48, observation), do: observation.day2_chaos

  defp interpolate(observation, fraction) do
    observation.day0_chaos + fraction * (observation.day1_chaos - observation.day0_chaos)
  end

  defp historical_pattern_reference_gateway do
    Application.get_env(
      :poe_flip_finder,
      :historical_pattern_reference_gateway,
      PoeFlipFinder.Gateways.BundledHistoricalPatternReferenceGateway
    )
  end
end
