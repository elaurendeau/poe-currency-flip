defmodule PoeFlipFinder.SnapshotQueryGateway do
  @moduledoc """
  Read side of the generation-tag hot-swap (docs/SCHEMA.md § Ingestion
  state and market data) -- deliberately separate from
  `PoeFlipFinder.SnapshotRepositoryGateway`, which is write-only and owned
  by the ingestion use case (Interface Segregation: different callers,
  different lifecycles).
  """

  alias PoeFlipFinder.ExchangeMarketSnapshot

  @doc """
  All snapshots in the currently-active generation for one league. Empty
  if the league is unrecognized or no generation has ever gone live yet.
  """
  @callback find_active_snapshots(league_external_id :: String.t()) :: [
              ExchangeMarketSnapshot.t()
            ]
end
