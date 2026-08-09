defmodule PoeFlipFinder.Gateways.EctoSnapshotRepositoryGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.SnapshotRepositoryGateway`.
  `commit_generation/2` is the single short transaction docs/SCHEMA.md's
  "Refresh flow" step 3 describes -- the only moment new data becomes
  visible, implemented as one `Ecto.Multi`.
  """

  @behaviour PoeFlipFinder.SnapshotRepositoryGateway

  import Ecto.Query

  alias PoeFlipFinder.{ExchangeMarketSnapshot, IngestionFreshness}
  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.Repo

  @ingestion_state_id 1

  # The migration seeds active_generation_id=0 as the "no generation has
  # ever gone live yet" sentinel -- skip the purge then, since there's
  # nothing to delete.
  @no_generation_yet 0

  @impl true
  def read_ingestion_state do
    state = Repo.get!(Schema.ExchangeIngestionState, @ingestion_state_id)

    %IngestionFreshness{
      last_processed_change_id: state.last_processed_change_id,
      active_generation_refreshed_at: state.active_generation_refreshed_at
    }
  end

  @impl true
  def start_new_generation, do: System.system_time(:millisecond)

  # Postgres caps a single query at 65,535 bind parameters. Each row here
  # binds 15 columns, so a from-scratch ingestion catch-up spanning
  # thousands of pairs can exceed that in one `insert_all` -- verified
  # against a real production crash 2026-08-08 (~5,050-row generation,
  # 75,750 params). 4000 rows/chunk (60,000 params) stays safely under the
  # limit with headroom for column-count drift.
  @max_rows_per_insert 4000

  @impl true
  def save_snapshots(snapshots) do
    snapshots
    |> Enum.map(&to_schema_attrs/1)
    |> Enum.chunk_every(@max_rows_per_insert)
    |> Enum.each(&Repo.insert_all(Schema.ExchangeMarketSnapshot, &1))

    :ok
  end

  @impl true
  def commit_generation(generation_id, new_last_processed_change_id) do
    now = DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.run(:state, fn repo, _changes ->
      {:ok, repo.get!(Schema.ExchangeIngestionState, @ingestion_state_id)}
    end)
    |> Ecto.Multi.update(:updated_state, fn %{state: state} ->
      Ecto.Changeset.change(state,
        active_generation_id: generation_id,
        last_processed_change_id: new_last_processed_change_id,
        active_generation_refreshed_at: now,
        updated_at: now
      )
    end)
    |> Ecto.Multi.run(:purge_superseded_generation, fn repo, %{state: state} ->
      purge_generation(repo, state.active_generation_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok

      {:error, step, reason, _changes} ->
        raise "commit_generation failed at #{inspect(step)}: #{inspect(reason)}"
    end
  end

  @impl true
  def discard_generation(generation_id) do
    purge_generation(Repo, generation_id)
    :ok
  end

  defp purge_generation(_repo, @no_generation_yet), do: {:ok, 0}

  defp purge_generation(repo, generation_id) do
    {count, _} =
      repo.delete_all(
        from s in Schema.ExchangeMarketSnapshot, where: s.generation_id == ^generation_id
      )

    {:ok, count}
  end

  defp to_schema_attrs(%ExchangeMarketSnapshot{} = snapshot) do
    %{
      generation_id: snapshot.generation_id,
      league_id: snapshot.league.id,
      currency_a_id: snapshot.currency_a.id,
      currency_b_id: snapshot.currency_b.id,
      snapshot_hour: snapshot.snapshot_hour,
      volume_traded_a: snapshot.volume_traded_a,
      volume_traded_b: snapshot.volume_traded_b,
      lowest_stock_a: snapshot.lowest_stock_a,
      highest_stock_a: snapshot.highest_stock_a,
      lowest_stock_b: snapshot.lowest_stock_b,
      highest_stock_b: snapshot.highest_stock_b,
      lowest_ratio_a: snapshot.lowest_ratio_a,
      highest_ratio_a: snapshot.highest_ratio_a,
      lowest_ratio_b: snapshot.lowest_ratio_b,
      highest_ratio_b: snapshot.highest_ratio_b
    }
  end
end
