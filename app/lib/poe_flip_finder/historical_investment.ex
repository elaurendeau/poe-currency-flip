defmodule PoeFlipFinder.HistoricalInvestment do
  @moduledoc """
  Ranks historical patterns by what their most-recently-sampled league did
  next from wherever the selected league currently is -- 1 day, 3 days, 1
  week, and 2 weeks out, per docs/PRD.md § 7.14. Every number is a real
  poe-antiquary observation from that one league (no interpolation, no
  cross-league averaging or "best of" cherry-picking).

  `HistoricalPricePattern.league_observations` is authored
  most-recent-league-first (verified: every entry in the bundled
  reference data has its newest sampled league at index 0) -- this
  context always reads `List.first/1` as "the last league" a candidate's
  numbers and trajectory graph are keyed to. A pattern whose last league
  has no real price at the current day doesn't fall back to an older
  league; it's simply excluded, so every displayed number stays traceable
  to one real, named league.

  Where the pattern's category is one this app's own Currency Exchange
  ingestion already tracks, today's real live price is resolved from the
  same `exchange_market_snapshot` data Features A/B/C/E already read --
  no new external dependency for that half.
  """

  alias PoeFlipFinder.{BaseCurrencyIds, Currency, DivineChaosRate, HistoricalPricePattern, League}
  alias PoeFlipFinder.HistoricalPricePattern.{DayPrice, LeagueObservation}

  # Categories poe-antiquary has real data for but that never trade on the
  # Currency Exchange (docs/DATA_SOURCES.md § Historical League Price
  # Archive) -- a live cross-check is never attempted for these.
  @historical_only_categories [:cluster_jewels]

  # {assign key, days out}. Order here is display/sort order, per docs/PRD.md § 7.14.
  @horizons [day_1: 1, day_3: 3, week_1: 7, week_2: 14]

  @type horizon_key :: :day_1 | :day_3 | :week_1 | :week_2
  @type horizon_value :: %{days: pos_integer(), chaos: float(), gain_pct: float()}
  @type live_price :: {:ok, float()} | :no_live_market | :not_traded_this_refresh

  @type candidate :: %{
          pattern: HistoricalPricePattern.t(),
          league: String.t(),
          today_day: non_neg_integer(),
          today_chaos: float(),
          horizons: %{horizon_key() => horizon_value() | nil},
          trajectory: [DayPrice.t()],
          live_price: live_price()
        }

  @spec list_patterns() :: [HistoricalPricePattern.t()]
  def list_patterns, do: historical_pattern_reference_gateway().find_all()

  @doc """
  The deepest league-day the *last* (most recent) sampled league has a
  real price for, across every curated pattern -- an inherent scope
  boundary, not a configurable setting: a league this many days old or
  older will never find a "today" price to build a candidate from, no
  matter how many patterns exist. Used to make that boundary explicit in
  the UI rather than let an empty result read as "nothing is worth
  buying." `nil` only if the reference data is completely empty.
  """
  @spec max_sampled_day() :: non_neg_integer() | nil
  def max_sampled_day do
    list_patterns()
    |> Enum.flat_map(fn pattern ->
      case List.first(pattern.league_observations) do
        nil -> []
        observation -> observation.day_prices
      end
    end)
    |> Enum.map(& &1.day)
    |> Enum.max(fn -> nil end)
  end

  @type elapsed :: %{days: non_neg_integer(), hours_into_day: non_neg_integer()}

  @doc """
  How far into `league` we are right now, per its real GGG `startAt`
  (docs/PRD.md § 7.14's known prerequisite, now wired up) -- both the day
  index (what ranking evidence keys off) and the hour-of-day remainder
  (for the "Day 2, 14h in" display, docs/PRD.md § 7.14). `:unknown` for a
  league whose start time was never captured -- never a guessed value.
  """
  @spec current_league_elapsed(League.t()) :: {:ok, elapsed()} | :unknown
  def current_league_elapsed(%League{start_at: nil}), do: :unknown

  def current_league_elapsed(%League{start_at: start_at}) do
    total_hours = DateTime.diff(clock().now(), start_at, :hour)

    if total_hours < 0,
      do: :unknown,
      else: {:ok, %{days: div(total_hours, 24), hours_into_day: rem(total_hours, 24)}}
  end

  @doc "Just the day index from current_league_elapsed/1 -- what ranking evidence keys off."
  @spec current_league_day(League.t()) :: {:ok, non_neg_integer()} | :unknown
  def current_league_day(%League{} = league) do
    case current_league_elapsed(league) do
      {:ok, %{days: days}} -> {:ok, days}
      :unknown -> :unknown
    end
  end

  @doc """
  Candidates for `league`, evaluated as of whatever day of `league` it
  currently is, unsorted (see `sort_by_horizon/3`). `:unknown_league_start`
  when `league.start_at` hasn't been captured -- the caller decides how to
  render that, this never falls back to a guessed day.
  """
  @spec compute_candidates(League.t()) :: {:ok, [candidate()]} | :unknown_league_start
  def compute_candidates(%League{} = league) do
    case current_league_day(league) do
      :unknown ->
        :unknown_league_start

      {:ok, day} ->
        snapshots = snapshot_query_gateway().find_active_snapshots(league.external_id)
        rate = DivineChaosRate.resolve(snapshots)

        candidates =
          list_patterns()
          |> Enum.map(&build_candidate(&1, day, snapshots, rate))
          |> Enum.reject(&is_nil/1)

        {:ok, candidates}
    end
  end

  @doc """
  Sorts `candidates` by their value at `horizon_key` (e.g. `:day_1`),
  descending by default (biggest riser first). Ranks by that horizon's
  `gain_pct`, not its raw `chaos` value -- a candidate's absolute chaos
  price is a function of the item's own denomination (a Mirror of
  Kalandra "moving" 5% is still a bigger number than a whole Chaos Orb),
  not of whether it's actually worth watching. Candidates with no real
  data at that horizon sort after every candidate that has some, in
  either direction -- "unknown" is never treated as "worst."
  """
  @spec sort_by_horizon([candidate()], horizon_key(), :asc | :desc) :: [candidate()]
  def sort_by_horizon(candidates, horizon_key, direction \\ :desc) do
    {with_value, without_value} =
      Enum.split_with(candidates, &(!is_nil(&1.horizons[horizon_key])))

    Enum.sort_by(with_value, & &1.horizons[horizon_key].gain_pct, direction) ++ without_value
  end

  defp build_candidate(%HistoricalPricePattern{} = pattern, day, snapshots, rate) do
    with observation when not is_nil(observation) <- List.first(pattern.league_observations),
         %{chaos: today_chaos} <- find_day(observation, day) do
      %{
        pattern: pattern,
        league: observation.league,
        today_day: day,
        today_chaos: today_chaos,
        horizons: build_horizons(observation, day, today_chaos),
        trajectory: observation.day_prices,
        live_price: resolve_live_price(pattern.currency, snapshots, rate)
      }
    else
      _ -> nil
    end
  end

  defp build_horizons(observation, today_day, today_chaos) do
    Map.new(@horizons, fn {key, offset} ->
      value =
        case find_day(observation, today_day + offset) do
          nil ->
            nil

          %{chaos: chaos} ->
            %{days: offset, chaos: chaos, gain_pct: (chaos - today_chaos) / today_chaos * 100}
        end

      {key, value}
    end)
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
  defp chaos_equivalent(
         other_currency,
         target_lowest,
         target_highest,
         other_lowest,
         other_highest,
         rate
       ) do
    cond do
      # A real market snapshot can carry a zero ratio on one side (thin/
      # edge-case data, not a programmer error) -- dividing by it would
      # crash the whole LiveView process on live production data, per the
      # real ArithmeticError this raised against a genuine Allflame
      # snapshot during manual verification. Treated as "no price
      # available from this snapshot," same as no snapshot matching at
      # all, not a fatal error.
      target_lowest == 0 or target_highest == 0 ->
        nil

      other_currency.external_id == BaseCurrencyIds.chaos_external_id() ->
        average(other_lowest / target_lowest, other_highest / target_highest)

      other_currency.external_id == BaseCurrencyIds.divine_external_id() and not is_nil(rate) ->
        average(other_lowest / target_lowest, other_highest / target_highest) *
          rate.chaos_per_divine

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
