defmodule PoeFlipFinder.Gateways.EctoLeagueReferenceGatewayTest do
  use PoeFlipFinder.DataCase, async: true

  alias PoeFlipFinder.Gateways.EctoLeagueReferenceGateway
  alias PoeFlipFinder.Gateways.Schema

  test "creates a league on first sight from a raw ingestion payload string" do
    result = EctoLeagueReferenceGateway.resolve_or_create_league("SomePrivateLeague")

    assert result.external_id == "SomePrivateLeague"
    # Best-guess-populated from the raw string -- no richer metadata
    # available at this seam.
    assert result.display_name == "SomePrivateLeague"
    assert result.has_exchange_activity == true
    persisted = Repo.get_by!(Schema.League, external_id: "SomePrivateLeague")
    # A league discovered only via ingestion is not known-to-GGG.
    assert persisted.known_to_ggg == false
  end

  test "marks has_exchange_activity on an existing league without touching its other fields" do
    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: "Allflame",
      display_name: "Allflame",
      is_current: true,
      has_exchange_activity: false,
      known_to_ggg: true
    )
    |> Repo.insert!()

    result = EctoLeagueReferenceGateway.resolve_or_create_league("Allflame")

    assert result.has_exchange_activity == true
    assert result.is_current == true
    assert result.display_name == "Allflame"
  end
end
