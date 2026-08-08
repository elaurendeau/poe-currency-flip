defmodule PoeFlipFinder.StubDivinationCardReferenceGateway do
  @moduledoc """
  A controllable `PoeFlipFinder.DivinationCardReferenceGateway` for testing
  `FlipOpportunities`'s wiring in isolation from the real bundled catalog.
  This is a legitimate one-layer-up substitution per
  docs/ELIXIR_TEST_MANIFESTO.md -- the gateway's own parsing is
  `BundledDivinationCardReferenceGatewayTest`'s job; this proves what
  `FlipOpportunities` does with a known set of card rewards.
  """

  @behaviour PoeFlipFinder.DivinationCardReferenceGateway

  @impl true
  def find_all, do: Process.get(__MODULE__, [])

  @doc "Configures what find_all/0 returns in the current test process."
  def stub(card_rewards), do: Process.put(__MODULE__, card_rewards)
end
