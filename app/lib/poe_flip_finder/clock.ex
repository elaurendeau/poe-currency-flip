defmodule PoeFlipFinder.Clock do
  @moduledoc "Defined by the core so ingestion's first-run lookback math is testable with a fixed time."

  @callback now() :: DateTime.t()
end
