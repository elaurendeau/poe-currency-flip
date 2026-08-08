defmodule PoeFlipFinder.Gateways.SystemClock do
  @moduledoc "The real implementation of `PoeFlipFinder.Clock` -- the actual wall clock."

  @behaviour PoeFlipFinder.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
