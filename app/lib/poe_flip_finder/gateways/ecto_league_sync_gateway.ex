defmodule PoeFlipFinder.Gateways.EctoLeagueSyncGateway do
  @moduledoc "The imperative-shell implementation of `PoeFlipFinder.LeagueSyncGateway`."

  @behaviour PoeFlipFinder.LeagueSyncGateway

  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.League
  alias PoeFlipFinder.Repo

  @impl true
  def upsert_from_ggg(leagues), do: Enum.map(leagues, &upsert/1)

  defp upsert(%League{} = league) do
    existing = Repo.get_by(Schema.League, external_id: league.external_id)

    schema =
      existing || %Schema.League{external_id: league.external_id, has_exchange_activity: false}

    schema
    # has_exchange_activity is deliberately untouched -- only ingestion knows that.
    |> Ecto.Changeset.change(
      display_name: league.display_name,
      is_current: league.is_current,
      known_to_ggg: true
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
      has_exchange_activity: schema.has_exchange_activity
    }
  end
end
