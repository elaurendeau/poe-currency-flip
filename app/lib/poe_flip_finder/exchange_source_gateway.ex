defmodule PoeFlipFinder.ExchangeSourceGateway do
  @moduledoc """
  Defined by the core for whatever it needs from GGG's Currency Exchange
  change-stream (docs/ARCHITECTURE.md § Currency Exchange Ingestion).
  Callers use this without knowing whether the implementation is the real
  GGG API or a test double.
  """

  alias PoeFlipFinder.ExchangeChangeStreamPage

  @doc """
  Fetches one hour of raw market activity. Reaching the current,
  still-open hour is signaled by `page.at_tip?` -- see docs/DATA_SOURCES.md
  § Currency Exchange Data for the verified signal.
  """
  @callback fetch_hour(change_id :: integer()) ::
              {:ok, ExchangeChangeStreamPage.t()} | {:error, term()}
end
