defmodule PoeFlipFinder.SnapshotRepositoryGateway do
  @moduledoc """
  Defined by the core: the generation-tag hot-swap mechanics for
  exchange_ingestion_state / exchange_market_snapshot (docs/SCHEMA.md §
  Ingestion state and market data). Takes already-resolved entities in --
  currency/league resolution is `PoeFlipFinder.CurrencyReferenceGateway`'s
  and `PoeFlipFinder.LeagueReferenceGateway`'s job, not this seam's.
  """

  alias PoeFlipFinder.{ExchangeMarketSnapshot, IngestionFreshness}

  @callback read_ingestion_state() :: IngestionFreshness.t()

  @doc "Mints a new generation tag for this ingestion run's rows."
  @callback start_new_generation() :: integer()

  @callback save_snapshots(snapshots :: [ExchangeMarketSnapshot.t()]) :: :ok

  @doc """
  Atomically advances the checkpoint, flips the active generation, and
  purges the superseded generation's rows -- docs/SCHEMA.md's "Refresh
  flow" step 3, in one place. Called whether the walk reached the true
  tip or just hit its per-call hour cap -- both are a normal, successful
  stop (docs/ARCHITECTURE.md § Currency Exchange Ingestion).
  """
  @callback commit_generation(
              generation_id :: integer(),
              new_last_processed_change_id :: integer()
            ) :: :ok

  @doc "Discards a generation's rows without touching the active checkpoint -- a hard failure mid-walk."
  @callback discard_generation(generation_id :: integer()) :: :ok
end
