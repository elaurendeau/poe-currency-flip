defmodule PoeFlipFinder.StubClock do
  @moduledoc "A fixed `PoeFlipFinder.Clock` for deterministic first-run-lookback tests."

  @behaviour PoeFlipFinder.Clock

  @impl true
  def now, do: Process.get({__MODULE__, :now})

  def stub(datetime), do: Process.put({__MODULE__, :now}, datetime)
end
