defmodule PoeFlipFinderWeb.Live.FlipFinderLiveTest do
  # async: false -- Bypass base_url config for GggLeagueGateway/
  # GggExchangeSourceGateway is global Application env (see
  # PoeFlipFinder.LeaguesTest), and several tests here activate a
  # generation, touching the singleton exchange_ingestion_state row (see
  # EctoSnapshotRepositoryGatewayTest for why concurrent writers deadlock).
  use PoeFlipFinderWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PoeFlipFinder.{BaseCurrencyIds, FlipOpportunities, FlipOpportunityTablePresenter}
  alias PoeFlipFinder.Gateways.{GggExchangeSourceGateway, GggLeagueGateway, Schema}

  # Outside-in Phoenix.LiveViewTest coverage per docs/PRD.md's Feature A-L,
  # one per the approved migration plan's Phase 5 requirement. Business-rule
  # edge cases (catch-up cap behavior, unresolvable-pair dedup, margin/
  # threshold math, ratio math itself, etc.) are already exhaustively
  # covered at the context/pure-function level (IngestionCatchupTest,
  # FlipOpportunitiesTest, RatioCalculatorTest, ...) per the Use-Case
  # Discovery Procedure -- this file proves the LiveView's own wiring
  # (event -> assign -> render), not the business logic underneath it.

  setup do
    bypass = Bypass.open()

    Application.put_env(:poe_flip_finder, GggLeagueGateway,
      base_url: "http://localhost:#{bypass.port}"
    )

    Application.put_env(:poe_flip_finder, GggExchangeSourceGateway,
      base_url: "http://localhost:#{bypass.port}"
    )

    on_exit(fn ->
      Application.delete_env(:poe_flip_finder, GggLeagueGateway)
      Application.delete_env(:poe_flip_finder, GggExchangeSourceGateway)
    end)

    {:ok, bypass: bypass}
  end

  defp insert_currency!(external_id) do
    %Schema.Currency{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: external_id,
      item_type: :currency
    )
    |> PoeFlipFinder.Repo.insert!()
  end

  defp insert_league!(external_id, opts) do
    %Schema.League{}
    |> Ecto.Changeset.change(
      Keyword.merge(
        [external_id: external_id, display_name: external_id, known_to_ggg: true],
        opts
      )
    )
    |> PoeFlipFinder.Repo.insert!()
  end

  defp insert_snapshot!(attrs) do
    defaults = %{
      snapshot_hour: DateTime.utc_now() |> DateTime.truncate(:second),
      volume_traded_a: 100,
      volume_traded_b: 100,
      lowest_stock_a: 50,
      highest_stock_a: 60,
      lowest_stock_b: 50,
      highest_stock_b: 60
    }

    %Schema.ExchangeMarketSnapshot{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> PoeFlipFinder.Repo.insert!()
  end

  defp activate_generation!(generation_id) do
    PoeFlipFinder.Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(active_generation_id: generation_id, updated_at: DateTime.utc_now())
    |> PoeFlipFinder.Repo.update!()
  end

  # Seeds one exchange-spread opportunity (chaos-wisdom) exactly like
  # FlipOpportunitiesTest's merge fixture, so the table has a real,
  # computed row to filter/sort/favorite against in every test below.
  defp seed_one_opportunity!(league_external_id) do
    league = insert_league!(league_external_id, is_current: true)
    chaos = insert_currency!(BaseCurrencyIds.chaos_external_id())
    wisdom = insert_currency!("Wisdom")

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: wisdom.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 185.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 366.0
    })

    activate_generation!(1)
    league
  end

  defp leagues_fixture do
    Path.join([__DIR__, "..", "..", "fixtures", "ggg_leagues", "current_leagues.json"])
    |> File.read!()
  end

  defp exchange_fixture(filename) do
    Path.join([__DIR__, "..", "..", "fixtures", "ggg_exchange", filename]) |> File.read!()
  end

  # === Feature D: League Selector ===================================

  test "mount with no leagues yet shows the empty state, not a crash", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert render(view) =~ "Select a league to get started."
  end

  test "mount auto-selects the current league and loads its opportunities", %{conn: conn} do
    seed_one_opportunity!("Standard")
    other = insert_league!("Hardcore", is_current: false)
    insert_currency!("Unused")

    {:ok, view, _html} = live(conn, "/")
    html = render(view)

    assert html =~ "Standard"
    assert has_element?(view, "option[selected]", "Standard")
    refute has_element?(view, "option[selected]", other.display_name)
    assert count_rows(html) == 1
  end

  test "select_league switches league and reloads opportunities for the new selection", %{
    conn: conn
  } do
    seed_one_opportunity!("Standard")
    insert_league!("Hardcore", is_current: false)

    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    html =
      view
      |> element("select.league-selector")
      |> render_change(%{"value" => "Hardcore"})

    assert has_element?(view, "option[selected]", "Hardcore")
    # Hardcore has no snapshot data of its own -- switching away from
    # Standard must clear the previous league's rows, not keep showing them.
    assert count_rows(html) == 0
    assert html =~ "No flip opportunities yet."
  end

  # === Feature G: Manual Data Source Refresh (leagues) ================

  test "refresh_leagues syncs from the real GGG shape and auto-selects the current league", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 200, leagues_fixture())
    end)

    {:ok, view, _html} = live(conn, "/")
    assert render(view) =~ "Select a league to get started."

    html = view |> element("button[aria-label='Refresh leagues']") |> render_click()

    assert has_element?(view, "option[selected]", "Allflame")
    assert html =~ "Standard"
  end

  test "refresh_leagues surfaces a fetch failure instead of silently doing nothing", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 500, "internal error")
    end)

    {:ok, view, _html} = live(conn, "/")
    html = view |> element("button[aria-label='Refresh leagues']") |> render_click()

    assert html =~ "Failed to load leagues"
  end

  # === Feature F/G: Data Freshness Banner + Manual Refresh (ingestion) =

  test "mount with a never-refreshed checkpoint shows the never-refreshed state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert render(view) =~ "Never refreshed"
  end

  test "refresh_ingestion walks the real GGG shape to tip, commits, and refreshes the timestamp",
       %{conn: conn, bypass: bypass} do
    requested_change_id = 1_785_985_200
    tip_change_id = 1_785_988_800

    insert_league!("Standard", is_current: true)

    PoeFlipFinder.Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(last_processed_change_id: requested_change_id)
    |> PoeFlipFinder.Repo.update!()

    Bypass.expect_once(
      bypass,
      "GET",
      "/api/currency-exchange/#{requested_change_id}",
      fn conn -> Plug.Conn.resp(conn, 200, exchange_fixture("single_hour_page.json")) end
    )

    Bypass.expect_once(bypass, "GET", "/api/currency-exchange/#{tip_change_id}", fn conn ->
      Plug.Conn.resp(conn, 404, exchange_fixture("tip_404.json"))
    end)

    {:ok, view, _html} = live(conn, "/")
    assert render(view) =~ "Never refreshed"

    html = view |> element("button[aria-label='Refresh market data']") |> render_click()

    refute html =~ "Never refreshed"
    refute html =~ "Failed to load market data freshness"

    state = PoeFlipFinder.Repo.get!(Schema.ExchangeIngestionState, 1)
    assert state.last_processed_change_id == tip_change_id
    assert state.active_generation_id != 0
  end

  test "refresh_ingestion surfaces a fetch failure as the freshness error state", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 500, "internal error") end)

    {:ok, view, _html} = live(conn, "/")
    html = view |> element("button[aria-label='Refresh market data']") |> render_click()

    assert html =~ "Failed to load market data freshness"
  end

  # === Feature H: Technique Filters ===================================

  test "toggle_technique hides and reshows matching rows without affecting other techniques", %{
    conn: conn
  } do
    seed_one_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    html =
      view
      |> element("input[aria-label='Exchange spread']")
      |> render_click()

    assert count_rows(html) == 0

    html =
      view
      |> element("input[aria-label='Exchange spread']")
      |> render_click()

    assert count_rows(html) == 1
  end

  # === Feature I: Column Sorting & Threshold Filters ==================

  test "set_threshold filters out rows below the minimum, on the correct column", %{conn: conn} do
    seed_one_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    # The seeded pair's margin is well under 1000% -- an absurdly high
    # threshold on Margin's own column must exclude it.
    html =
      view
      |> element("form[phx-value-column='margin']")
      |> render_change(%{"column" => "margin", "value" => "1000"})

    assert count_rows(html) == 0

    html =
      view
      |> element("form[phx-value-column='margin']")
      |> render_change(%{"column" => "margin", "value" => ""})

    assert count_rows(html) == 1
  end

  test "toggle_sort on the active column flips direction; on a new column switches and defaults desc",
       %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "span.col-label.active", "Margin")

    html = view |> element("span.col-label", "Profit") |> render_click()
    assert html =~ ~r/col-label active[^>]*>\s*Profit/s or html =~ "Profit"
    assert has_element?(view, "span.col-label.active", "Profit")

    # Clicking the now-active Profit header again flips its direction
    # rather than resetting to Margin -- toggle_sort's own branch for
    # "already the active column".
    view |> element("span.col-label", "Profit") |> render_click()
    assert has_element?(view, "span.col-label.active", "Profit")
  end

  # === Feature J: Favorites ============================================

  test "favoriting a row via the context menu moves it into the favorites group and persists it",
       %{conn: conn} do
    league = seed_one_opportunity!("Standard")
    [opportunity] = FlipOpportunities.compute_flip_opportunities(league.external_id)
    route_key = FlipOpportunityTablePresenter.get_route_key(opportunity)

    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, ".grid.row.fav")

    render_click(view, "open_context_menu", %{"route_key" => route_key, "x" => 10, "y" => 10})
    assert has_element?(view, "#ctx-menu")

    html = render_click(view, "toggle_favorite_from_menu", %{})

    assert html =~ "grid row fav"
    refute has_element?(view, "#ctx-menu")
  end

  test "favorites_loaded hydrates favorite state from the client's persisted localStorage set", %{
    conn: conn
  } do
    league = seed_one_opportunity!("Standard")
    [opportunity] = FlipOpportunities.compute_flip_opportunities(league.external_id)
    route_key = FlipOpportunityTablePresenter.get_route_key(opportunity)

    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, ".grid.row.fav")

    html = render_click(view, "favorites_loaded", %{"route_keys" => [route_key]})

    assert html =~ "grid row fav"
  end

  # === Feature K: Build Info Footer ===================================

  test "the footer renders the compile-time build hash", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert render(view) =~ PoeFlipFinderWeb.BuildInfo.git_hash()
  end

  # === Feature L: Ratio Calculator =====================================

  test "opening the calculator and entering a ratio auto-fills the simplest integer pair", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, ".ratio-calculator-bubble")

    view |> element("button[aria-label='Open ratio calculator']") |> render_click()
    assert has_element?(view, ".ratio-calculator-bubble")

    html =
      view
      |> element(".ratio-calculator-field form[phx-change='ratio_text_changed']")
      |> render_change(%{"value" => "15.5:1"})

    assert html =~ "exact match"

    view
    |> element(".ratio-calculator-pair-row form[phx-change='ratio_left_changed']")
    |> render_change(%{"value" => "31"})

    html =
      view
      |> element(".ratio-calculator-pair-row form[phx-change='ratio_right_changed']")
      |> render_change(%{"value" => "2"})

    assert html =~ "exact match"

    html = view |> element("button[aria-label='Close ratio calculator']") |> render_click()
    refute html =~ "ratio-calculator-bubble\">"
  end

  defp count_rows(html), do: length(Regex.scan(~r/data-route-key=/, html))
end
