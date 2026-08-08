defmodule PoeFlipFinder.Ingestion do
  @moduledoc """
  Currency Exchange ingestion: the checkpoint/staleness read and the
  bounded catch-up walk (docs/ARCHITECTURE.md § Currency Exchange
  Ingestion).
  """

  alias PoeFlipFinder.{CatchupResult, ExchangeMarketSnapshot, IngestionFreshness}

  @doc "A simple pass-through read of the ingestion checkpoint/staleness state."
  @spec get_ingestion_freshness() :: IngestionFreshness.t()
  def get_ingestion_freshness, do: snapshot_repository_gateway().read_ingestion_state()

  @doc """
  Orchestrates one bounded catch-up walk (docs/ARCHITECTURE.md § Currency
  Exchange Ingestion). Hitting the per-call hour cap is a normal,
  successful stop -- it still commits what was gathered and reports
  itself as not fully caught up; only a hard failure from the source
  gateway discards the generation.
  """
  @spec run_ingestion_catchup(PoeFlipFinder.CatchupCapPolicy.t()) ::
          {:ok, CatchupResult.t()} | {:error, term()}
  def run_ingestion_catchup(cap_policy) do
    starting_change_id = resolve_starting_change_id(cap_policy)

    case exchange_source_gateway().fetch_hour(starting_change_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %{at_tip: true}} ->
        # Nothing new since the last commit. Minting and activating a new
        # (empty) generation here would purge the still-good active one
        # for zero gain -- never replace last-known-good data with worse
        # data (docs/ARCHITECTURE.md § Failure Handling). A no-op refresh
        # must be a true no-op: the active generation is untouched, and
        # the checkpoint doesn't need to move either, since it's already
        # at this same id.
        {:ok,
         %CatchupResult{
           hours_processed: 0,
           fully_caught_up: true,
           last_processed_change_id: starting_change_id,
           skipped_unresolvable_market_entry_count: 0
         }}

      {:ok, first_page} ->
        run_walk(starting_change_id, first_page, cap_policy)
    end
  end

  defp run_walk(starting_change_id, first_page, cap_policy) do
    generation_id = snapshot_repository_gateway().start_new_generation()

    case walk_forward(generation_id, starting_change_id, first_page, cap_policy) do
      {:ok, result} ->
        :ok =
          snapshot_repository_gateway().commit_generation(
            generation_id,
            result.last_processed_change_id
          )

        {:ok, result}

      {:error, reason} ->
        :ok = snapshot_repository_gateway().discard_generation(generation_id)
        {:error, reason}
    end
  end

  defp walk_forward(generation_id, starting_change_id, first_page, cap_policy) do
    initial_state = %{
      snapshots_by_pair: %{},
      unresolved_pairs: MapSet.new(),
      currency_cache: %{},
      league_cache: %{}
    }

    do_walk(generation_id, starting_change_id, first_page, cap_policy, 0, initial_state)
  end

  defp do_walk(_generation_id, change_id, %{at_tip: true}, _cap_policy, hours_processed, state) do
    finalize(change_id, hours_processed, state, true)
  end

  defp do_walk(generation_id, _change_id, page, cap_policy, hours_processed, state) do
    state = process_entries(generation_id, page.entries, state)
    hours_processed = hours_processed + 1
    change_id = page.next_change_id

    if hours_processed < cap_policy.max_hours_per_call do
      case exchange_source_gateway().fetch_hour(change_id) do
        {:error, reason} ->
          {:error, reason}

        {:ok, next_page} ->
          do_walk(generation_id, change_id, next_page, cap_policy, hours_processed, state)
      end
    else
      finalize(change_id, hours_processed, state, false)
    end
  end

  defp finalize(last_processed_change_id, hours_processed, state, fully_caught_up) do
    :ok = snapshot_repository_gateway().save_snapshots(Map.values(state.snapshots_by_pair))

    {:ok,
     %CatchupResult{
       hours_processed: hours_processed,
       fully_caught_up: fully_caught_up,
       last_processed_change_id: last_processed_change_id,
       skipped_unresolvable_market_entry_count: MapSet.size(state.unresolved_pairs)
     }}
  end

  defp process_entries(generation_id, entries, state) do
    Enum.reduce(entries, state, fn entry, state ->
      case resolve_snapshot(generation_id, entry, state) do
        {:ok, snapshot, state} ->
          put_in(state.snapshots_by_pair[snapshot_key(snapshot)], snapshot)

        {:error, state} ->
          update_in(state.unresolved_pairs, &MapSet.put(&1, unresolved_pair_key(entry)))
      end
    end)
  end

  defp resolve_snapshot(generation_id, entry, state) do
    with {:ok, currency_a, state} <- resolve_currency(entry.currency_a_external_id, state),
         {:ok, currency_b, state} <- resolve_currency(entry.currency_b_external_id, state) do
      {league, state} = resolve_league(entry.league_external_id, state)

      snapshot = %ExchangeMarketSnapshot{
        id: nil,
        generation_id: generation_id,
        league: league,
        currency_a: currency_a,
        currency_b: currency_b,
        snapshot_hour: entry.snapshot_hour,
        volume_traded_a: entry.volume_traded_a,
        volume_traded_b: entry.volume_traded_b,
        lowest_stock_a: entry.lowest_stock_a,
        highest_stock_a: entry.highest_stock_a,
        lowest_stock_b: entry.lowest_stock_b,
        highest_stock_b: entry.highest_stock_b,
        lowest_ratio_a: entry.lowest_ratio_a,
        highest_ratio_a: entry.highest_ratio_a,
        lowest_ratio_b: entry.lowest_ratio_b,
        highest_ratio_b: entry.highest_ratio_b
      }

      {:ok, snapshot, state}
    else
      {:error, state} -> {:error, state}
    end
  end

  defp resolve_currency(external_id, state) do
    case Map.fetch(state.currency_cache, external_id) do
      {:ok, cached} ->
        {:ok, cached, state}

      :error ->
        case currency_reference_gateway().resolve_or_create_currency(external_id) do
          nil -> {:error, state}
          currency -> {:ok, currency, put_in(state.currency_cache[external_id], currency)}
        end
    end
  end

  defp resolve_league(external_id, state) do
    case Map.fetch(state.league_cache, external_id) do
      {:ok, cached} ->
        {cached, state}

      :error ->
        league = league_reference_gateway().resolve_or_create_league(external_id)
        {league, put_in(state.league_cache[external_id], league)}
    end
  end

  defp snapshot_key(snapshot),
    do: {snapshot.league.id, snapshot.currency_a.id, snapshot.currency_b.id}

  defp unresolved_pair_key(entry),
    do: {entry.league_external_id, entry.currency_a_external_id, entry.currency_b_external_id}

  defp resolve_starting_change_id(cap_policy) do
    case snapshot_repository_gateway().read_ingestion_state() do
      %IngestionFreshness{last_processed_change_id: nil} ->
        first_run_starting_change_id(cap_policy)

      %IngestionFreshness{last_processed_change_id: change_id} ->
        change_id
    end
  end

  # No stored checkpoint yet -- seed near "now" rather than Currency
  # Exchange's actual launch; old data has no product value (see
  # docs/PRD.md § 4 Non-Goals: no historical trend charts).
  defp first_run_starting_change_id(cap_policy) do
    now_epoch_second = clock().now() |> DateTime.to_unix()
    current_hour_epoch_second = div(now_epoch_second, 3600) * 3600
    current_hour_epoch_second - cap_policy.first_run_lookback_hours * 3600
  end

  defp exchange_source_gateway do
    Application.get_env(
      :poe_flip_finder,
      :exchange_source_gateway,
      PoeFlipFinder.Gateways.GggExchangeSourceGateway
    )
  end

  defp currency_reference_gateway do
    Application.get_env(
      :poe_flip_finder,
      :currency_reference_gateway,
      PoeFlipFinder.Gateways.EctoCurrencyReferenceGateway
    )
  end

  defp league_reference_gateway do
    Application.get_env(
      :poe_flip_finder,
      :league_reference_gateway,
      PoeFlipFinder.Gateways.EctoLeagueReferenceGateway
    )
  end

  defp snapshot_repository_gateway do
    Application.get_env(
      :poe_flip_finder,
      :snapshot_repository_gateway,
      PoeFlipFinder.Gateways.EctoSnapshotRepositoryGateway
    )
  end

  defp clock do
    Application.get_env(:poe_flip_finder, :clock, PoeFlipFinder.Gateways.SystemClock)
  end
end
