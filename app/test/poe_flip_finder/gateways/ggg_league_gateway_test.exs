defmodule PoeFlipFinder.Gateways.GggLeagueGatewayTest do
  # async: false -- PoeFlipFinder.LeaguesTest also configures this same
  # module's base_url via Application.put_env, which is global process
  # state, not test-isolated. Two async tests racing to set it to
  # different Bypass ports intermittently sent a request to the wrong
  # instance. Same class of gotcha as the singleton-DB-row deadlock in
  # EctoSnapshotRepositoryGatewayTest -- shared mutable state outside the
  # SQL Sandbox needs the same care.
  use ExUnit.Case, async: false

  alias PoeFlipFinder.Gateways.GggLeagueGateway

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: a saved real API
  # response in, an asserted normalized domain object out, served through
  # Bypass so the real HTTP client path is exercised too.

  setup do
    bypass = Bypass.open()

    Application.put_env(:poe_flip_finder, GggLeagueGateway,
      base_url: "http://localhost:#{bypass.port}"
    )

    on_exit(fn -> Application.delete_env(:poe_flip_finder, GggLeagueGateway) end)
    {:ok, bypass: bypass}
  end

  defp expect_leagues_fixture(bypass) do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 200, fixture())
    end)
  end

  test "excludes Solo Self-Found leagues", %{bypass: bypass} do
    expect_leagues_fixture(bypass)

    {:ok, leagues} = GggLeagueGateway.fetch_leagues()
    external_ids = Enum.map(leagues, & &1.external_id)

    assert Enum.sort(external_ids) ==
             Enum.sort(["Standard", "Allflame", "Hardcore Allflame", "Ruthless Allflame"])

    refute "Solo Self-Found" in external_ids
    refute "SSF Allflame" in external_ids
  end

  test "marks only the mainline variant of the current challenge league as current", %{
    bypass: bypass
  } do
    expect_leagues_fixture(bypass)

    {:ok, leagues} = GggLeagueGateway.fetch_leagues()

    assert find_by_external_id(leagues, "Standard").is_current == false
    assert find_by_external_id(leagues, "Allflame").is_current == true
    assert find_by_external_id(leagues, "Hardcore Allflame").is_current == false
    assert find_by_external_id(leagues, "Ruthless Allflame").is_current == false
  end

  test "marks exactly one league as current", %{bypass: bypass} do
    expect_leagues_fixture(bypass)

    {:ok, leagues} = GggLeagueGateway.fetch_leagues()

    assert Enum.count(leagues, & &1.is_current) == 1
  end

  test "defers exchange activity to a later ingestion cross-check", %{bypass: bypass} do
    expect_leagues_fixture(bypass)

    {:ok, leagues} = GggLeagueGateway.fetch_leagues()

    assert Enum.all?(leagues, &(&1.has_exchange_activity == false))
  end

  test "parses startAt into a real DateTime, per docs/PRD.md § 7.14's day-of-league need", %{
    bypass: bypass
  } do
    expect_leagues_fixture(bypass)

    {:ok, leagues} = GggLeagueGateway.fetch_leagues()

    assert find_by_external_id(leagues, "Allflame").start_at ==
             ~U[2026-07-24 20:00:00Z]
  end

  test "an unexpected HTTP status is a reported error", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 500, "internal error")
    end)

    assert {:error, {:unexpected_status, 500}} = GggLeagueGateway.fetch_leagues()
  end

  defp find_by_external_id(leagues, external_id) do
    Enum.find(leagues, &(&1.external_id == external_id))
  end

  defp fixture do
    Path.join([__DIR__, "..", "..", "fixtures", "ggg_leagues", "current_leagues.json"])
    |> File.read!()
  end
end
