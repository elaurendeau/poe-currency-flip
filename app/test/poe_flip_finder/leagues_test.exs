defmodule PoeFlipFinder.LeaguesTest do
  # async: false -- shares Application-env config for GggLeagueGateway's
  # base_url with PoeFlipFinder.Gateways.GggLeagueGatewayTest; see that
  # file for why concurrent writers to that global config race.
  use PoeFlipFinder.DataCase, async: false

  alias PoeFlipFinder.Gateways.{GggLeagueGateway, Schema}
  alias PoeFlipFinder.Leagues

  # Context-level integration test per docs/ELIXIR_TEST_MANIFESTO.md: the
  # real GGG gateway (Bypass-backed, not mocked) and the real Ecto-backed
  # sync gateway, proving the actual orchestration end to end.

  setup do
    bypass = Bypass.open()

    Application.put_env(:poe_flip_finder, GggLeagueGateway,
      base_url: "http://localhost:#{bypass.port}"
    )

    on_exit(fn -> Application.delete_env(:poe_flip_finder, GggLeagueGateway) end)
    {:ok, bypass: bypass}
  end

  defp leagues_fixture do
    Path.join([__DIR__, "..", "fixtures", "ggg_leagues", "current_leagues.json"]) |> File.read!()
  end

  test "resolve_league_list/0 reads only leagues already synced and known to GGG" do
    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: "Standard",
      display_name: "Standard",
      known_to_ggg: true
    )
    |> Repo.insert!()

    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: "PrivateLeague",
      display_name: "PrivateLeague",
      known_to_ggg: false
    )
    |> Repo.insert!()

    leagues = Leagues.resolve_league_list()

    assert Enum.map(leagues, & &1.external_id) == ["Standard"]
  end

  test "refresh_league_list/0 fetches live then syncs into the cache, returning the synced result",
       %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 200, leagues_fixture())
    end)

    {:ok, leagues} = Leagues.refresh_league_list()

    assert Enum.map(leagues, & &1.external_id) |> Enum.sort() ==
             Enum.sort(["Standard", "Allflame", "Hardcore Allflame", "Ruthless Allflame"])

    # Actually persisted, not just returned -- resolve_league_list/0 (the
    # DB-cached read) must see it too.
    assert Enum.map(Leagues.resolve_league_list(), & &1.external_id) |> Enum.sort() ==
             Enum.sort(["Standard", "Allflame", "Hardcore Allflame", "Ruthless Allflame"])
  end

  test "refresh_league_list/0 with no leagues from GGG persists nothing and returns an empty list",
       %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn -> Plug.Conn.resp(conn, 200, "[]") end)

    assert {:ok, []} = Leagues.refresh_league_list()
    assert Leagues.resolve_league_list() == []
  end

  test "refresh_league_list/0 propagates a fetch failure rather than swallowing it", %{
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 500, "internal error")
    end)

    assert {:error, _reason} = Leagues.refresh_league_list()
  end
end
