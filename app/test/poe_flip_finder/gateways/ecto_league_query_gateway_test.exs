defmodule PoeFlipFinder.Gateways.EctoLeagueQueryGatewayTest do
  use PoeFlipFinder.DataCase, async: true

  alias PoeFlipFinder.Gateways.EctoLeagueQueryGateway
  alias PoeFlipFinder.Gateways.Schema

  defp insert_league!(attrs) do
    %Schema.League{}
    |> Ecto.Changeset.change(
      Map.merge(%{is_current: false, has_exchange_activity: false, known_to_ggg: false}, attrs)
    )
    |> Repo.insert!()
  end

  test "returns only leagues confirmed known to GGG" do
    insert_league!(%{external_id: "Standard", display_name: "Standard", known_to_ggg: true})

    insert_league!(%{
      external_id: "PrivateLeague",
      display_name: "PrivateLeague",
      known_to_ggg: false
    })

    leagues = EctoLeagueQueryGateway.find_all_leagues()

    assert Enum.map(leagues, & &1.external_id) == ["Standard"]
  end

  test "carries through is_current and has_exchange_activity flags" do
    insert_league!(%{
      external_id: "Allflame",
      display_name: "Allflame",
      known_to_ggg: true,
      is_current: true,
      has_exchange_activity: true
    })

    [league] = EctoLeagueQueryGateway.find_all_leagues()

    assert league.is_current == true
    assert league.has_exchange_activity == true
  end
end
