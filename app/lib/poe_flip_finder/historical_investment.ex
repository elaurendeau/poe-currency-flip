defmodule PoeFlipFinder.HistoricalInvestment do
  @moduledoc """
  Answers "which of the sampled historical patterns has real evidence for
  what happens next, starting from where the selected league actually is
  right now" -- docs/PRD.md § 7.14 Feature N.

  Deliberately day-relative and evidence-only: every number is a real
  poe-antiquary observation (no interpolation), and a pattern only appears
  when at least one sampled league has a real price at both the current
  league-day and the day after it. Where the pattern's category is one
  this app's own Currency Exchange ingestion already tracks, today's real
  live price is resolved from the same `exchange_market_snapshot` data
  Features A/B/C/E already read -- no new external dependency for that
  half.
  """

  alias PoeFlipFinder.HistoricalPricePattern.LeagueObservation
  alias PoeFlipFinder.{BaseCurrencyIds, Currency, DivineChaosRate, HistoricalPricePattern, League}

  # Categories poe-antiquary has real data for but that never trade on the
  # Currency Exchange (docs/DATA_SOURCES.md § Historical League Price
  # Archive) -- a live cross-check is never attempted for these.
  @historical_only_categories [:cluster_jewels]

  @type league_evidence :: %{
          league: String.t(),
          day_chaos: float(),
          next_day_chaos: float(),
          gain_pct: float(),
          units: non_neg_integer(),
          affordable: boolean(),
          projected_value_chaos: float() | nil
        }

  @type live_price :: {:ok, float()} | :no_live_market | :not_traded_this_refresh

  @type candidate :: %{
          pattern: HistoricalPricePattern.t(),
          league_evidence: [league_evidence()],
          confidence_total: pos_integer(),
          confidence_rising: non_neg_integer(),
          best_gain_pct: float(),
          live_price: live_price()
        }

  @spec list_patterns() :: [HistoricalPricePattern.t()]
  def list_patterns, do: historical_pattern_reference_gateway().find_all()

  @doc """
  How many days into `league` we are right now, per its real GGG `startAt`
  (docs/PRD.md § 7.14's known prerequisite, now wired up). `:unknown` for
  a league whose start time was never captured -- never a guessed day.
  """
  @spec current_league_day(League.t()) :: {:ok, non_neg_integer()} | :unknown
  def current_league_day(%League{start_at: nil}), do: :unknown

  def current_league_day(%League{start_at: start_at}) do
    day = DateTime.diff(clock().now(), start_at, :day)
    if day < 0, do: :unknown, else: {:ok, day}
  end

  @doc """
  Ranked candidates for `league` at `investment_amount` Chaos, evaluated
  as of whatever day of `league` it currently is. `:unknown_league_start`
  when `league.start_at` hasn't been captured -- the caller decides how to
  render that, this never falls back to a guessed day.
  """
  @spec compute_candidates(League.t(), number()) ::
          {:ok, [candidate()]} | :unknown_league_start
  def compute_candidates(%League{} = league, investment_amount)
      when is_number(investment_amount) and investment_amount > 0 do
    case current_league_day(league) do
      :unknown ->
        :unknown_league_start

      {:ok, day} ->
        snapshots = snapshot_query_gateway().find_active_snapshots(league.external_id)
        rate = DivineChaosRate.resolve(snapshots)

        candidates =
          list_patterns()
          |> Enum.map(&build_candidate(&1, day, investment_amount, snapshots, rate))
          |> Enum.filter(&(&1.league_evidence != []))
          |> Enum.sort_by(& &1.best_gain_pct, :desc)

        {:ok, candidates}
    end
  end

  defp build_candidate(%HistoricalPricePattern{} = pattern, day, investment_amount, snapshots, rate) do
    evidence =
      pattern.league_observations
      |> Enum.map(&evidence_for_day(&1, day, investment_amount))
      |> Enum.reject(&is_nil/1)

    %{
      pattern: pattern,
      league_evidence: evidence,
      confidence_total: length(evidence),
      confidence_rising: Enum.count(evidence, &(&1.gain_pct > 0)),
      best_gain_pct: evidence |> Enum.map(& &1.gain_pct) |> Enum.max(fn -> 0.0 end),
      live_price: resolve_live_price(pattern.currency, snapshots, rate)
    }
  end

  # nil when this league observation has no real price at both `day` and
  # `day + 1` -- never interpolated, never a stale nearby day standing in.
  defp evidence_for_day(%LeagueObservation{} = observation, day, investment_amount) do
    with %{chaos: day_chaos} <- find_day(observation, day),
         %{chaos: next_day_chaos} <- find_day(observation, day + 1) do
      units = trunc(investment_amount / day_chaos)

      %{
        league: observation.league,
        day_chaos: day_chaos,
        next_day_chaos: next_day_chaos,
        gain_pct: (next_day_chaos - day_chaos) / day_chaos * 100,
        units: units,
        affordable: units > 0,
        projected_value_chaos: if(units > 0, do: units * next_day_chaos, else: nil)
      }
    else
      nil -> nil
    end
  end

  defp find_day(%LeagueObservation{day_prices: day_prices}, day) do
    Enum.find(day_prices, &(&1.day == day))
  end

  defp resolve_live_price(%Currency{category: category}, _snapshots, _rate)
       when category in @historical_only_categories,
       do: :no_live_market

  defp resolve_live_price(%Currency{} = currency, snapshots, rate) do
    snapshots
    |> Enum.find_value(&match_snapshot(&1, currency.display_name, rate))
    |> case do
      nil -> :not_traded_this_refresh
      price -> {:ok, price}
    end
  end

  defp match_snapshot(snapshot, display_name, rate) do
    cond do
      snapshot.currency_a.display_name == display_name ->
        chaos_equivalent(
          snapshot.currency_b,
          snapshot.lowest_ratio_a,
          snapshot.highest_ratio_a,
          snapshot.lowest_ratio_b,
          snapshot.highest_ratio_b,
          rate
        )

      snapshot.currency_b.display_name == display_name ->
        chaos_equivalent(
          snapshot.currency_a,
          snapshot.lowest_ratio_b,
          snapshot.highest_ratio_b,
          snapshot.lowest_ratio_a,
          snapshot.highest_ratio_a,
          rate
        )

      true ->
        nil
    end
  end

  # target_ratio_*/other_ratio_* are the two sides' raw paired quantities
  # at the same quote extreme (e.g. "365 Scroll : 1 Chaos"), not
  # already-normalized per-unit prices -- same convention DivineChaosRate
  # uses: price of target, expressed in other's units, is
  # other_ratio / target_ratio. The *other* side of the pair must be Chaos
  # or Divine for this to be a meaningful chaos-equivalent point estimate.
  defp chaos_equivalent(other_currency, target_lowest, target_highest, other_lowest, other_highest, rate) do
    cond do
      other_currency.external_id == BaseCurrencyIds.chaos_external_id() ->
        average(other_lowest / target_lowest, other_highest / target_highest)

      other_currency.external_id == BaseCurrencyIds.divine_external_id() and not is_nil(rate) ->
        average(other_lowest / target_lowest, other_highest / target_highest) * rate.chaos_per_divine

      true ->
        nil
    end
  end

  defp average(a, b), do: (a + b) / 2.0

  defp historical_pattern_reference_gateway do
    Application.get_env(
      :poe_flip_finder,
      :historical_pattern_reference_gateway,
      PoeFlipFinder.Gateways.BundledHistoricalPatternReferenceGateway
    )
  end

  defp snapshot_query_gateway do
    Application.get_env(
      :poe_flip_finder,
      :snapshot_query_gateway,
      PoeFlipFinder.Gateways.EctoSnapshotQueryGateway
    )
  end

  defp clock do
    Application.get_env(:poe_flip_finder, :clock, PoeFlipFinder.Gateways.SystemClock)
  end
end
