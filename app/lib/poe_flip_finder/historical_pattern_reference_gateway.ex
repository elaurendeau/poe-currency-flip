defmodule PoeFlipFinder.HistoricalPatternReferenceGateway do
  @moduledoc """
  Defined by the core for whatever it needs from historical league price
  pattern data (docs/DATA_SOURCES.md § Historical League Price Archive).
  """

  alias PoeFlipFinder.HistoricalPricePattern

  @callback find_all() :: [HistoricalPricePattern.t()]
end
