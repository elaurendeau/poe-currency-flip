defmodule PoeFlipFinder.StubHistoricalPatternReferenceGateway do
  @moduledoc """
  A controllable `PoeFlipFinder.HistoricalPatternReferenceGateway` for
  testing `HistoricalInvestment`'s ranking/live-cross-check wiring against
  a known, small set of patterns -- the real bundled catalog's own parsing
  is `BundledHistoricalPatternReferenceGatewayTest`'s job, per
  docs/ELIXIR_TEST_MANIFESTO.md's one-layer-up substitution.
  """

  @behaviour PoeFlipFinder.HistoricalPatternReferenceGateway

  @impl true
  def find_all, do: Process.get(__MODULE__, [])

  @doc "Configures what find_all/0 returns in the current test process."
  def stub(patterns), do: Process.put(__MODULE__, patterns)
end
