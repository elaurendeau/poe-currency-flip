defmodule PoeFlipFinder.StubSnapshotRepositoryGateway do
  @moduledoc """
  A controllable `PoeFlipFinder.SnapshotRepositoryGateway` for testing
  `Ingestion.run_ingestion_catchup/1`'s own orchestration -- records every
  call so tests can assert on what was (or wasn't) invoked, the way the
  Java version's Mockito `verify(...)` calls do.
  """

  @behaviour PoeFlipFinder.SnapshotRepositoryGateway

  @impl true
  def read_ingestion_state, do: Process.get({__MODULE__, :ingestion_state})

  @impl true
  def start_new_generation, do: Process.get({__MODULE__, :new_generation})

  @impl true
  def save_snapshots(snapshots) do
    record({:save_snapshots, snapshots})
    :ok
  end

  @impl true
  def commit_generation(generation_id, new_last_processed_change_id) do
    record({:commit_generation, generation_id, new_last_processed_change_id})
    :ok
  end

  @impl true
  def discard_generation(generation_id) do
    record({:discard_generation, generation_id})

    case Process.get({__MODULE__, :discard_raises}) do
      nil -> :ok
      fun -> fun.()
    end
  end

  def stub_ingestion_state(freshness), do: Process.put({__MODULE__, :ingestion_state}, freshness)

  def stub_new_generation(generation_id),
    do: Process.put({__MODULE__, :new_generation}, generation_id)

  def stub_discard_generation_raises(fun), do: Process.put({__MODULE__, :discard_raises}, fun)

  @doc "Calls recorded so far, oldest first."
  def calls, do: Process.get({__MODULE__, :calls}, []) |> Enum.reverse()

  defp record(call),
    do: Process.put({__MODULE__, :calls}, [call | Process.get({__MODULE__, :calls}, [])])
end
