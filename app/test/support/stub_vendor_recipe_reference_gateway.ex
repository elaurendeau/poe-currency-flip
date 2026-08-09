defmodule PoeFlipFinder.StubVendorRecipeReferenceGateway do
  @moduledoc """
  A controllable `PoeFlipFinder.VendorRecipeReferenceGateway` for testing
  `FlipOpportunities`'s wiring in isolation from the real bundled catalog.
  This is a legitimate one-layer-up substitution per
  docs/ELIXIR_TEST_MANIFESTO.md -- the gateway's own parsing is
  `BundledVendorRecipeReferenceGatewayTest`'s job; this proves what
  `FlipOpportunities` does with a known set of vendor recipes.
  """

  @behaviour PoeFlipFinder.VendorRecipeReferenceGateway

  @impl true
  def find_all, do: Process.get(__MODULE__, [])

  @doc "Configures what find_all/0 returns in the current test process."
  def stub(vendor_recipes), do: Process.put(__MODULE__, vendor_recipes)
end
