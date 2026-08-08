defmodule PoeFlipFinder.StubLeagueReferenceGateway do
  @moduledoc "A controllable `PoeFlipFinder.LeagueReferenceGateway` for testing ingestion's own orchestration."

  @behaviour PoeFlipFinder.LeagueReferenceGateway

  @impl true
  def resolve_or_create_league(league_external_id),
    do: Process.get({__MODULE__, league_external_id})

  def stub(league_external_id, result), do: Process.put({__MODULE__, league_external_id}, result)
end
