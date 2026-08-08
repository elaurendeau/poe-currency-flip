defmodule PoeFlipFinder.StubItemIconGateway do
  @moduledoc """
  A controllable `PoeFlipFinder.ItemIconGateway` for testing
  `EctoCurrencyReferenceGateway`'s upsert logic in isolation from the real
  catalog. This is a legitimate one-layer-up substitution per
  docs/ELIXIR_TEST_MANIFESTO.md -- the test here isn't proving the item
  icon gateway itself (that's `GggItemIconGatewayTest`'s job), it's proving
  what `EctoCurrencyReferenceGateway` does with a known lookup result.
  """

  @behaviour PoeFlipFinder.ItemIconGateway

  @impl true
  def lookup_item(external_id) do
    Process.get({__MODULE__, external_id})
  end

  @doc "Configures what lookup_item/1 returns for a given external_id in the current test process."
  def stub(external_id, result), do: Process.put({__MODULE__, external_id}, result)
end
