defmodule PoeFlipFinder.StubCurrencyReferenceGateway do
  @moduledoc "A controllable `PoeFlipFinder.CurrencyReferenceGateway` for testing ingestion's own orchestration."

  @behaviour PoeFlipFinder.CurrencyReferenceGateway

  @impl true
  def resolve_or_create_currency(external_id), do: Process.get({__MODULE__, external_id})

  def stub(external_id, result), do: Process.put({__MODULE__, external_id}, result)
end
