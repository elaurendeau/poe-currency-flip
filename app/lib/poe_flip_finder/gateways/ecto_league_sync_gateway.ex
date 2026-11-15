defmodule PoeFlipFinder.Gateways.EctoLeagueSyncGateway do
  @moduledoc "The imperative-shell implementation of `PoeFlipFinder.LeagueSyncGateway`."

  @behaviour PoeFlipFinder.LeagueSyncGateway

  import Ecto.Query

  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.League
  alias PoeFlipFinder.Repo

  @impl true
  # An empty list is anomalous (GGG outage/maintenance returning 200 with no
  # leagues), not "every league ended" -- never treated as grounds to unflag
  # the whole cache.
  def upsert_from_ggg([]), do: []

  def upsert_from_ggg(leagues) do
    upserted = Enum.map(leagues, &upsert/1)
    unflag_leagues_missing_from(Enum.map(leagues, & &1.external_id))
    upserted
  end

  # GGG drops a league from its list once it ends, but the upsert above only
  # ever touches leagues GGG *returned* -- so an ended league kept its stale
  # known_to_ggg/is_current flags forever, still showing in the dropdown and
  # winning the default-league pick over the real current one. The row (and
  # whatever ingestion learned about it) stays; only the GGG-derived flags clear.
  defp unflag_leagues_missing_from(fetched_external_ids) do
    Schema.League
    |> where([l], l.external_id not in ^fetched_external_ids)
    |> where([l], l.known_to_ggg or l.is_current)
    |> Repo.update_all(set: [known_to_ggg: false, is_current: false])
  end

  defp upsert(%League{} = league) do
    existing = Repo.get_by(Schema.League, external_id: league.external_id)

    schema =
      existing || %Schema.League{external_id: league.external_id, has_exchange_activity: false}

    schema
    # has_exchange_activity is deliberately untouched -- only ingestion knows that.
    |> Ecto.Changeset.change(
      display_name: league.display_name,
      is_current: league.is_current,
      known_to_ggg: true,
      start_at: league.start_at
    )
    |> Repo.insert_or_update!()
    |> to_entity()
  end

  defp to_entity(%Schema.League{} = schema) do
    %League{
      id: schema.id,
      external_id: schema.external_id,
      display_name: schema.display_name,
      is_current: schema.is_current,
      has_exchange_activity: schema.has_exchange_activity,
      start_at: schema.start_at
    }
  end
end
