defmodule PoeFlipFinder.Gateways.EctoLeagueQueryGateway do
  @moduledoc "The imperative-shell implementation of `PoeFlipFinder.LeagueQueryGateway`."

  @behaviour PoeFlipFinder.LeagueQueryGateway

  import Ecto.Query

  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.League
  alias PoeFlipFinder.Repo

  @impl true
  def find_all_leagues do
    # Only leagues an actual GGG Leagues API sync has confirmed exist --
    # never the private/one-off league names ingestion sees in raw trade
    # data (see Schema.League's known_to_ggg).
    Schema.League
    |> where(known_to_ggg: true)
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  defp to_entity(%Schema.League{} = schema) do
    %League{
      id: schema.id,
      external_id: schema.external_id,
      display_name: schema.display_name,
      is_current: schema.is_current,
      has_exchange_activity: schema.has_exchange_activity
    }
  end
end
