defmodule PoeFlipFinder.Gateways.EctoLeagueReferenceGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.LeagueReferenceGateway`.
  On create, best-guess-populates both external_id and display_name from
  the raw league string in the exchange payload -- no richer metadata is
  available at this seam. See docs/ARCHITECTURE.md's explicit follow-up: a
  later task should let league resolution enrich this via the live
  Leagues API instead.
  """

  @behaviour PoeFlipFinder.LeagueReferenceGateway

  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.League
  alias PoeFlipFinder.Repo

  @impl true
  def resolve_or_create_league(league_external_id) do
    existing = Repo.get_by(Schema.League, external_id: league_external_id)

    schema =
      existing ||
        %Schema.League{
          external_id: league_external_id,
          display_name: league_external_id,
          is_current: false,
          known_to_ggg: false
        }

    schema
    |> Ecto.Changeset.change(has_exchange_activity: true)
    |> Repo.insert_or_update!()
    |> to_entity()
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
