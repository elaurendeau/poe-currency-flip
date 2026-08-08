defmodule PoeFlipFinder.StubExchangeSourceGateway do
  @moduledoc """
  A controllable `PoeFlipFinder.ExchangeSourceGateway` for testing
  `Ingestion.run_ingestion_catchup/1`'s own orchestration in isolation from
  the real GGG adapter (already proven by `GggExchangeSourceGatewayTest`).
  """

  @behaviour PoeFlipFinder.ExchangeSourceGateway

  @impl true
  def fetch_hour(change_id) do
    responses = Process.get({__MODULE__, :responses}, %{})

    case Map.fetch(responses, change_id) do
      {:ok, response} -> response
      :error -> compute(change_id)
    end
  end

  defp compute(change_id) do
    case Process.get({__MODULE__, :compute_fn}) do
      nil -> {:error, :not_stubbed}
      fun -> fun.(change_id)
    end
  end

  @doc "Stubs a fixed response for one specific change_id."
  def stub(change_id, response) do
    Process.put(
      {__MODULE__, :responses},
      Map.put(Process.get({__MODULE__, :responses}, %{}), change_id, response)
    )
  end

  @doc "Stubs a fallback response computed from whatever change_id is requested, for any id not fixed via stub/2."
  def stub_computed(fun), do: Process.put({__MODULE__, :compute_fn}, fun)
end
