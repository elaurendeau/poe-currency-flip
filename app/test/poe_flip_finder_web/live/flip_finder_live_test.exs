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

  defp insert_currency!(external_id, display_name \\ nil, category \\ :currency) do
    %Schema.Currency{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: display_name || external_id,
      category: category
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
      highest_ratio_b: 366.0,
      # {1, 185} makes the volume-weighted sell average land exactly on the
      # 185 extreme (see UndercutQuote's moduledoc) -- insert_snapshot!'s
      # default {100, 100} would instead average to 1.0, cratering the
      # sell price to 2 and inflating margin to ~18000%, since 100/100 is
      # an arbitrary placeholder unrelated to this fixture's 185/366 ratio.
      volume_traded_a: 1,
      volume_traded_b: 185
    })

    activate_generation!(1)
    league
  end

  # Seeds one divination-card opportunity using a real entry from the
  # bundled reference catalog (docs/PRD.md § 7.3) rather than a stubbed
  # gateway -- BundledDivinationCardReferenceGateway caches via
  # :persistent_term, which (unlike a Process-dictionary-based stub) is
  # visible from the LiveView's own process, not just this test process.
  # "Chaotic Disposition" (stackSize 1, reward 5x Chaos Orb, predictable)
  # needs no separate resale-leg snapshot: its reward *is* Chaos, resolved
  # directly. Its `via` is still a two-step chain (card, then reward),
  # unlike every other technique's single-item via, per
  # docs/mockups/flip-row-reference.html's own Divination Card example row.
  defp seed_one_divination_card_opportunity!(league_external_id) do
    league = insert_league!(league_external_id, is_current: true)
    chaos = insert_currency!(BaseCurrencyIds.chaos_external_id(), "Chaos Orb")
    divine = insert_currency!(BaseCurrencyIds.divine_external_id(), "Divine Orb")

    card =
      insert_currency!(
        "Metadata/Items/DivinationCards/DivinationCardChaoticDisposition",
        "Chaotic Disposition",
        :cards
      )

    # Divination Card needs the Chaos<->Divine reference rate to compute
    # anything at all (DivineChaosRate.resolve returning nil short-circuits
    # DivinationCardOpportunityFinder to []).
    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: divine.id,
      lowest_ratio_a: 210.0,
      lowest_ratio_b: 1.0,
      highest_ratio_a: 210.0,
      highest_ratio_b: 1.0
    })

    # Flat 1:5 chaos:card ratio -> suggested_buy_price=4 (card per chaos).
    # cost_in_base = stack_size(1)/4 = 0.25 chaos -- same hand-verified
    # "≈0.25c per card" detail as DivinationCardOpportunityFinderTest's
    # golden path.
    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: card.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 5.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 5.0
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

  # === Feature C: Divination Card Flip Finder ========================

  test "renders a divination card row's full via chain (card, then reward), not just the card",
       %{conn: conn} do
    # Regression test: the row template used to render only hd(@opportunity.via),
    # which was correct while every technique had a single-item via list, but
    # silently dropped the reward step once Divination Card's two-item via
    # (card, then reward) started flowing through -- a real gap relative to
    # docs/mockups/flip-row-reference.html's own Divination Card example row
    # ("5 The Vanity -> 1 Regal Orb").
    seed_one_divination_card_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")

    # Anchored on "≈0.25c per card" (this scenario's hand-verified detail
    # string) rather than "Test Card" alone -- Exchange Spread independently
    # produces its own single-item row off the same chaos-card snapshot, so
    # matching on the card's name alone would ambiguously match two rows.
    row_html =
      view
      |> element(".grid.row", "≈0.25c per card")
      |> render()

    assert row_html =~ "Chaotic Disposition"
    assert row_html =~ "Chaos Orb"
    assert row_html =~ "class=\"arrow\""
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

    # The fetch runs via start_async, not inline in handle_event -- render_click
    # returns as soon as the event handler itself returns, which is BEFORE the
    # async task resolves, so this is the spinner state, not the final one
    # (docs/PRD.md's data-freshness UX: a refresh in flight must be visibly
    # spinning, not silent until it completes).
    click_html = view |> element("button[aria-label='Refresh leagues']") |> render_click()
    assert click_html =~ "league-refresh-button__icon--spinning"
    assert click_html =~ "Refreshing leagues…"

    html = render_async(view, 2000)
    refute html =~ "league-refresh-button__icon--spinning"
    assert has_element?(view, "option[selected]", "Allflame")
    assert html =~ "Standard"
    # docs/PRD.md § 7.7: the temporary status banner confirms completion --
    # separate from (and in addition to) the league selector itself updating.
    refute html =~ "Refreshing leagues…"
    assert html =~ "Leagues refreshed"
  end

  test "refresh_leagues also recomputes the Historical Investment tab, not just opportunities", %{
    conn: conn,
    bypass: bypass
  } do
    # Regression test: refresh_leagues's handle_async originally only
    # called load_opportunities/1, not load_historical_candidates/1.
    # selected_league itself was still updated correctly (a plain assign),
    # but @historical_candidates/@league_day silently kept whatever they
    # were computed against *before* the refresh (here: :no_league_selected,
    # from mount with an empty DB) -- so the tab kept showing "Select a
    # league to get started" even though a real league (with a real
    # startAt from the GGG fixture) was now genuinely selected.
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 200, leagues_fixture())
    end)

    {:ok, view, _html} = live(conn, "/")
    view |> element("button[aria-label='Refresh leagues']") |> render_click()
    render_async(view, 2000)

    html = view |> element("button.tab-button", "Historical Investment") |> render_click()

    refute html =~ "Select a league to get started"
  end

  test "refresh_leagues surfaces a fetch failure instead of silently doing nothing", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/leagues", fn conn ->
      Plug.Conn.resp(conn, 500, "internal error")
    end)

    {:ok, view, _html} = live(conn, "/")
    view |> element("button[aria-label='Refresh leagues']") |> render_click()
    html = render_async(view, 2000)

    assert html =~ "Failed to load leagues"
    # docs/PRD.md § 7.7: a failure is reported only via the existing
    # persistent error state -- the temporary banner is cleared, not
    # repurposed into a second place to look for the same failure.
    refute html =~ "Refreshing leagues…"
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

    click_html = view |> element("button[aria-label='Refresh market data']") |> render_click()
    assert click_html =~ "league-refresh-button__icon--spinning"
    assert click_html =~ "Refreshing market data…"

    html = render_async(view, 2000)
    refute html =~ "league-refresh-button__icon--spinning"
    refute html =~ "Never refreshed"
    refute html =~ "Failed to load market data freshness"
    # docs/PRD.md § 7.6: one hour of real new data was processed here (the
    # single fixture page, then the tip) -- the "found new data" outcome,
    # not "already caught up" or "partial progress".
    refute html =~ "Refreshing market data…"
    assert html =~ "Found new data (1h processed)"

    state = PoeFlipFinder.Repo.get!(Schema.ExchangeIngestionState, 1)
    assert state.last_processed_change_id == tip_change_id
    assert state.active_generation_id != 0
  end

  test "refresh_ingestion already at the tip shows the already-caught-up banner with an ETA", %{
    conn: conn,
    bypass: bypass
  } do
    # 10 minutes into the current bucket -- leaves ~50 minutes until the
    # next one, comfortably clear of both the "under a minute" boundary and
    # any minute-rollover flakiness from real test execution time.
    tip_change_id = System.system_time(:second) - 600
    insert_league!("Standard", is_current: true)

    PoeFlipFinder.Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(last_processed_change_id: tip_change_id)
    |> PoeFlipFinder.Repo.update!()

    Bypass.expect_once(bypass, "GET", "/api/currency-exchange/#{tip_change_id}", fn conn ->
      body = Jason.encode!(%{next_change_id: tip_change_id, markets: []})
      Plug.Conn.resp(conn, 404, body)
    end)

    {:ok, view, _html} = live(conn, "/")
    view |> element("button[aria-label='Refresh market data']") |> render_click()
    html = render_async(view, 2000)

    # docs/PRD.md § 7.6: "already caught up" gets an explicit statement plus
    # a computed ETA until new data will actually be available (derived from
    # the real checkpoint's next-hour boundary), not a guess.
    assert [_, minutes] = Regex.run(~r/Already caught up · next data in ~(\d+)m/, html)
    assert String.to_integer(minutes) in 45..50
  end

  test "refresh_ingestion hitting the per-call hour cap shows the partial-progress banner", %{
    conn: conn,
    bypass: bypass
  } do
    requested_change_id = 1_785_985_200
    insert_league!("Standard", is_current: true)

    PoeFlipFinder.Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(last_processed_change_id: requested_change_id)
    |> PoeFlipFinder.Repo.update!()

    Application.put_env(:poe_flip_finder, :ingestion, max_hours_per_call: 1)
    on_exit(fn -> Application.delete_env(:poe_flip_finder, :ingestion) end)

    Bypass.expect_once(
      bypass,
      "GET",
      "/api/currency-exchange/#{requested_change_id}",
      fn conn -> Plug.Conn.resp(conn, 200, exchange_fixture("single_hour_page.json")) end
    )

    {:ok, view, _html} = live(conn, "/")
    view |> element("button[aria-label='Refresh market data']") |> render_click()
    html = render_async(view, 2000)

    assert html =~ "Partial progress (1h) — refresh again to continue"
  end

  test "refresh_ingestion surfaces a fetch failure as the freshness error state", %{
    conn: conn,
    bypass: bypass
  } do
    Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 500, "internal error") end)

    {:ok, view, _html} = live(conn, "/")
    view |> element("button[aria-label='Refresh market data']") |> render_click()
    html = render_async(view, 2000)

    assert html =~ "Failed to load market data freshness"
    # docs/PRD.md § 7.6: same rule as leagues -- a failure only ever shows up
    # via the persistent error state, never via the temporary banner.
    refute html =~ "Refreshing market data…"
  end

  # === Feature H: Technique Filters ===================================

  # Seeds one vendor-recipe opportunity using a real single-hop entry from
  # the bundled reference catalog (docs/PRD.md § 7.1) rather than a stubbed
  # gateway -- same rationale as seed_one_divination_card_opportunity!/1:
  # BundledVendorRecipeReferenceGateway caches via :persistent_term, visible
  # from the LiveView's own process. "Scroll of Wisdom" (3x) -> "Portal
  # Scroll" (1x) is the first captured recipe (docs/DATA_SOURCES.md).
  defp seed_one_vendor_recipe_opportunity!(league_external_id) do
    league = insert_league!(league_external_id, is_current: true)
    chaos = insert_currency!(BaseCurrencyIds.chaos_external_id(), "Chaos Orb")
    divine = insert_currency!(BaseCurrencyIds.divine_external_id(), "Divine Orb")

    wisdom =
      insert_currency!("Metadata/Items/Currency/CurrencyIdentification", "Scroll of Wisdom")

    portal = insert_currency!("Metadata/Items/Currency/CurrencyPortal", "Portal Scroll")

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: divine.id,
      lowest_ratio_a: 210.0,
      lowest_ratio_b: 1.0,
      highest_ratio_a: 210.0,
      highest_ratio_b: 1.0
    })

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: wisdom.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 5.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 5.0
    })

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: portal.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 2.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 2.0
    })

    activate_generation!(1)
    league
  end

  # === Grand Exchange Flip / Vendor Flip tabs ===========================

  test "the Grand Exchange Flip tab is active by default and shows only its own techniques", %{
    conn: conn
  } do
    seed_one_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "button.tab-button--active", "Grand Exchange Flip")
    assert has_element?(view, "input[aria-label='Exchange spread']")
    refute has_element?(view, "input[aria-label='Vendor recipe']")
    assert count_rows(render(view)) == 1
  end

  test "switching to the Vendor Flip tab shows vendor recipe rows and hides Grand Exchange ones",
       %{conn: conn} do
    seed_one_vendor_recipe_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    # Grand Exchange Flip is active by default. The seeded snapshots also
    # feed Exchange Spread rows for the same chaos-anchored pairs (expected
    # -- that's a different technique looking at the same market data), but
    # no vendor_recipe row is ever included in this tab's rendered output.
    refute render(view) =~ ~s(data-route-key="vendor_recipe|)

    html = view |> element("button.tab-button", "Vendor Flip") |> render_click()

    assert has_element?(view, "button.tab-button--active", "Vendor Flip")
    # Vendor Flip has exactly one technique -- nothing to filter it against,
    # so it shows no checkbox at all (Vendor Recipe is simply always on).
    refute has_element?(view, ".filter-bar")
    assert html =~ ~s(data-route-key="vendor_recipe|)
    refute html =~ ~s(data-route-key="exchange_spread|)
  end

  test "Vendor Recipe stays on under the Vendor Flip tab even if a prior session persisted it off",
       %{conn: conn} do
    seed_one_vendor_recipe_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    # Simulates a value saved back when the checkbox still existed --
    # without the always-on override, this would leave the technique
    # permanently, invisibly disabled with no checkbox left to re-enable it.
    render_click(view, "display_preferences_loaded", %{
      "active_tab" => "vendor",
      "enabled_techniques" => %{"vendor_recipe" => false}
    })

    assert has_element?(view, "button.tab-button--active", "Vendor Flip")
    assert render(view) =~ ~s(data-route-key="vendor_recipe|)
  end

  test "the Historical Investment tab shows day-relative candidates with icons, live price, and 4 horizons",
       %{conn: conn} do
    # The selected/current league's own name/start_at is independent of
    # which real HISTORICAL league (Ancestors/Mirage) backs each
    # candidate's numbers -- "Necropolis" here is just this test's chosen
    # name for the league the user is currently viewing, with start_at=now
    # (day 0). This deliberately exercises the real bundled gateway end to
    # end, not a stub, per docs/ELIXIR_TEST_MANIFESTO.md's outside-in default.
    insert_league!("Necropolis",
      is_current: true,
      start_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, "button.tab-button--disabled", "Historical Investment")

    html = view |> element("button.tab-button", "Historical Investment") |> render_click()

    assert html =~ "Day 0"
    assert html =~ "Ancient Orb"
    assert html =~ "Ancestors, day 0"
    # Real Ancestors day-0 (2.45c), day-1 (3.51c), day-3 (3.7c), day-7 (4.28c), day-14 (3.56c).
    assert html =~ "+43%"
    assert html =~ "+51%"
    assert html =~ "+75%"
    assert html =~ "+45%"
    # An icon resolved from the real bundled Item Icons catalog by name.
    assert html =~ "AncientOrb.png"
    # A trajectory sparkline (SVG), per docs/PRD.md § 7.14.
    assert html =~ "<svg" and html =~ "sparkline"
    # A real hover description captured from the PoE Wiki, per
    # docs/DATA_SOURCES.md -- not just the bare item name repeated.
    assert html =~ "Reforges a unique equipment as another of the same item class"
  end

  test "an item with no captured description still renders, with an Unknown hover tooltip",
       %{conn: conn} do
    # "Acid Slitherer" (Beast) has no description captured -- Beasts'
    # real usage lives on a PoE Wiki table this project hasn't found a
    # query path into yet (see docs/DATA_SOURCES.md). The missing
    # description must never hide the item itself, only fall back to an
    # honest "Unknown" tooltip.
    insert_league!("Necropolis",
      is_current: true,
      start_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    {:ok, view, _html} = live(conn, "/")
    html = view |> element("button.tab-button", "Historical Investment") |> render_click()

    assert html =~ "Acid Slitherer"

    doc = Floki.parse_document!(html)

    acid_slitherer_wrapper =
      doc
      |> Floki.find(".historical-name")
      |> Enum.find(fn el -> Floki.text(el) =~ "Acid Slitherer" end)

    assert acid_slitherer_wrapper
    assert Floki.attribute(acid_slitherer_wrapper, "title") == ["Unknown"]
  end

  test "the Historical Investment tab respects the shared category drawer filter", %{conn: conn} do
    insert_league!("Necropolis",
      is_current: true,
      start_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    {:ok, view, _html} = live(conn, "/")
    view |> element("button.tab-button", "Historical Investment") |> render_click()

    assert render(view) =~ "Ancient Orb"

    html =
      render_click(view, "toggle_category", %{"category" => "currency"})

    refute html =~ "Ancient Orb"
    # A non-currency category (e.g. a Cluster Jewel) stays visible.
    assert html =~ "Cluster Jewel"
  end

  test "toggle_historical_sort flips the Next day sort direction", %{conn: conn} do
    insert_league!("Necropolis",
      is_current: true,
      start_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    {:ok, view, _html} = live(conn, "/")
    view |> element("button.tab-button", "Historical Investment") |> render_click()

    # Descending by default -- the best Next-day riser should render before a worse one.
    # At day 0 in the bundled reference data, Ancient Orb's real day0->day1
    # move (2.45c -> 3.51c, +43%) beats this Fire Damage cluster jewel's
    # (4.15c -> 3.9c, -6%).
    #
    # Matched by exact candidate-name text (via Floki), not a raw HTML
    # substring search -- the dataset also contains "Eldritch Exalted Orb",
    # "Hunter's Exalted Orb", etc., which a bare `String.contains?`/
    # `:binary.match` on "Ancient Orb"/"Orb" would collide with once the
    # reference data grew past a handful of curated items.
    fire_damage_name = "Large Cluster Jewel (8 passives, Lv68): 12% increased Fire Damage"

    html = render(view)
    assert String.contains?(html, "Cluster Jewel") and String.contains?(html, "Ancient Orb")

    assert candidate_name_index(html, "Ancient Orb") <
             candidate_name_index(html, fire_damage_name)

    # All 4 horizon columns carry the "historical-sort" class now that
    # each is independently clickable -- target the active one (Next day)
    # specifically rather than the ambiguous ".historical-sort" selector.
    flipped_html =
      view |> element("span.historical-sort", "Next day") |> render_click()

    assert candidate_name_index(flipped_html, fire_damage_name) <
             candidate_name_index(flipped_html, "Ancient Orb")
  end

  test "clicking a different horizon column switches to it and defaults to descending",
       %{conn: conn} do
    insert_league!("Necropolis",
      is_current: true,
      start_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    {:ok, view, _html} = live(conn, "/")
    view |> element("button.tab-button", "Historical Investment") |> render_click()

    assert has_element?(view, "span.col-label.active", "Next day")

    view |> element("span.historical-sort", "Next 3 days") |> render_click()

    assert has_element?(view, "span.col-label.active", "Next 3 days")
    refute has_element?(view, "span.col-label.active", "Next day")

    assert_push_event(view, "persist_display_preferences", %{
      historical_sort_column: :day_3,
      historical_sort_direction: :desc
    })

    # Clicking the now-active "Next 3 days" header again flips its
    # direction rather than resetting to "Next day" -- same
    # already-active-column branch toggle_sort's own tests cover for the
    # other tabs' sort columns.
    view |> element("span.historical-sort", "Next 3 days") |> render_click()
    assert has_element?(view, "span.col-label.active", "Next 3 days")

    assert_push_event(view, "persist_display_preferences", %{
      historical_sort_column: :day_3,
      historical_sort_direction: :asc
    })
  end

  # Exact candidate-name match (via Floki), not a raw HTML substring search --
  # the dataset also contains "Eldritch Exalted Orb", "Hunter's Exalted Orb",
  # etc., which a bare `String.contains?`/`:binary.match` on "Exalted Orb"
  # would collide with once the reference data grew past a handful of items.
  defp candidate_name_index(html, exact_name) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".candidate-name")
    |> Enum.map(&(Floki.text(&1) |> String.trim()))
    |> Enum.find_index(&(&1 == exact_name))
  end

  test "a league with no captured start time shows the explicit unknown state, never a guessed day",
       %{conn: conn} do
    insert_league!("Standard", is_current: true, start_at: nil)

    {:ok, view, _html} = live(conn, "/")
    html = view |> element("button.tab-button", "Historical Investment") |> render_click()

    assert html =~ "league start time unknown"
  end

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

  # === Feature M: Currency Category Filter =============================

  test "the category drawer is hidden until the hamburger toggle opens it, with every category selected by default",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, ".category-drawer")

    html = view |> element("button.category-menu-toggle") |> render_click()

    assert has_element?(view, ".category-drawer")
    # 23 categories, all selected by default (docs/PRD.md § 7.13).
    # 24 categories (23 GGG-tradeable + Cluster Jewels, docs/PRD.md § 7.14), all selected by default.
    assert length(Regex.scan(~r/category-item--selected/, html)) == 24
    assert has_element?(view, "[phx-value-category='currency'].category-item--selected")
  end

  test "Deselect all clears every category and Select all restores them, hiding/reshowing rows",
       %{conn: conn} do
    seed_one_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    view |> element("button.category-menu-toggle") |> render_click()

    html = view |> element(".category-drawer-action", "Deselect all") |> render_click()
    assert count_rows(html) == 0
    refute html =~ "category-item--selected"

    html = view |> element(".category-drawer-action", "Select all") |> render_click()
    assert count_rows(html) == 1

    # 24 categories (23 GGG-tradeable + Cluster Jewels, docs/PRD.md § 7.14), all selected by default.
    assert length(Regex.scan(~r/category-item--selected/, html)) == 24
  end

  test "toggle_category hides and reshows matching rows without affecting other categories", %{
    conn: conn
  } do
    seed_one_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    view |> element("button.category-menu-toggle") |> render_click()

    # The seeded opportunity's Via leg is Wisdom, category :currency.
    html = view |> element("[phx-value-category='currency']") |> render_click()
    assert count_rows(html) == 0
    refute has_element?(view, "[phx-value-category='currency'].category-item--selected")

    html = view |> element("[phx-value-category='currency']") |> render_click()
    assert count_rows(html) == 1
    assert has_element?(view, "[phx-value-category='currency'].category-item--selected")
  end

  test "a Divination Card row is filtered by its reward's category, not the card's own category",
       %{conn: conn} do
    seed_one_divination_card_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    # "≈0.25c per card" uniquely identifies the divination_card row (see the
    # Feature C test above) -- this scenario's snapshot data also produces
    # an unrelated exchange_spread row off the same chaos-card pair, so
    # asserting on the total row count would be fragile here.
    assert has_element?(view, ".grid.row", "≈0.25c per card")

    view |> element("button.category-menu-toggle") |> render_click()

    # The card itself is category :cards, but its reward here is Chaos Orb
    # (:currency) -- disabling :cards must NOT hide the divination_card row.
    view |> element("[phx-value-category='cards']") |> render_click()
    assert has_element?(view, ".grid.row", "≈0.25c per card")

    # Disabling :currency (the reward's real category) must hide it.
    view |> element("[phx-value-category='currency']") |> render_click()
    refute has_element?(view, ".grid.row", "≈0.25c per card")
  end

  test "toggling a category persists the updated preference", %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")

    view |> element("button.category-menu-toggle") |> render_click()
    view |> element("[phx-value-category='oils']") |> render_click()

    assert_push_event(view, "persist_display_preferences", %{
      enabled_categories: %{currency: true, oils: false}
    })
  end

  test "Deselect all and Select all each persist the bulk update", %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")

    view |> element("button.category-menu-toggle") |> render_click()

    view |> element(".category-drawer-action", "Deselect all") |> render_click()

    assert_push_event(view, "persist_display_preferences", %{
      enabled_categories: %{currency: false, oils: false}
    })

    view |> element(".category-drawer-action", "Select all") |> render_click()

    assert_push_event(view, "persist_display_preferences", %{
      enabled_categories: %{currency: true, oils: true}
    })
  end

  test "display_preferences_loaded applies a saved category filter", %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    html =
      render_click(view, "display_preferences_loaded", %{
        "enabled_categories" => %{"currency" => false}
      })

    assert count_rows(html) == 0
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

  test "set_max_start filters out rows whose Chaos-normalized start exceeds the cap", %{
    conn: conn
  } do
    seed_one_opportunity!("Standard")

    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    # The seeded pair starts at 1 Chaos -- a cap below that must exclude it.
    html =
      view
      |> element("form[phx-change='set_max_start']")
      |> render_change(%{"value" => "0.5"})

    assert count_rows(html) == 0

    html =
      view
      |> element("form[phx-change='set_max_start']")
      |> render_change(%{"value" => ""})

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

  # === Features H/I: Persisted Display Preferences =====================
  # docs/PRD.md § 7.8/7.9: technique filters, sort column/direction, and
  # thresholds are a per-browser preference, same mechanism as Favorites.

  test "toggling a technique, sorting, and setting a threshold each persist the updated preferences",
       %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")

    view |> element("input[aria-label='Exchange spread']") |> render_click()

    assert_push_event(view, "persist_display_preferences", %{
      enabled_techniques: %{
        vendor_recipe: true,
        exchange_spread: false,
        divination_card: true,
        bulk_buy: true
      },
      sort_column: :margin,
      sort_direction: :desc,
      thresholds: %{}
    })

    view |> element("span.col-label", "Profit") |> render_click()
    assert_push_event(view, "persist_display_preferences", %{sort_column: :profit} = _payload)

    view
    |> element("form[phx-value-column='volume']")
    |> render_change(%{"column" => "volume", "value" => "50"})

    assert_push_event(view, "persist_display_preferences", %{thresholds: %{volume: 50.0}} = _)

    view
    |> element("form[phx-change='set_max_start']")
    |> render_change(%{"value" => "10"})

    assert_push_event(view, "persist_display_preferences", %{max_start_chaos: 10.0} = _)
  end

  test "display_preferences_loaded applies a saved technique filter, sort, and threshold", %{
    conn: conn
  } do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    html =
      render_click(view, "display_preferences_loaded", %{
        "enabled_techniques" => %{"exchange_spread" => false},
        "sort_column" => "profit",
        "sort_direction" => "asc",
        "thresholds" => %{"margin" => 5}
      })

    # exchange_spread is the seeded opportunity's own technique -- disabling
    # it via the loaded preference must filter the row out immediately.
    assert count_rows(html) == 0
    assert has_element?(view, "span.col-label.active", "Profit")
  end

  test "display_preferences_loaded applies a saved max_start_chaos", %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")
    assert count_rows(render(view)) == 1

    # The seeded pair starts at 1 Chaos -- a saved cap below that must
    # filter it out on load, exactly like a live set_max_start would.
    html =
      render_click(view, "display_preferences_loaded", %{"max_start_chaos" => "0.5"})

    assert count_rows(html) == 0
  end

  test "display_preferences_loaded with garbage input falls back to current defaults, not a crash",
       %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")

    html =
      render_click(view, "display_preferences_loaded", %{
        "enabled_techniques" => "not-a-map",
        "enabled_categories" => "not-a-map",
        "sort_column" => "not-a-real-column",
        "sort_direction" => 12_345,
        "thresholds" => ["also", "not", "a", "map"],
        "max_start_chaos" => %{"not" => "a-number"}
      })

    assert html =~ "PoE Flip Finder"
    assert has_element?(view, "span.col-label.active", "Margin")
    assert has_element?(view, "input[aria-label='Exchange spread'][checked]")
    # every category still defaults to enabled -- confirmed via the row
    # count rather than the (hidden-by-default) drawer's own markup.
    # A garbage max_start_chaos falls back to nil (no cap), so the row
    # isn't spuriously filtered out either.
    assert count_rows(html) == 1
  end

  test "display_preferences_loaded with a partially-valid payload applies only the valid fields",
       %{conn: conn} do
    seed_one_opportunity!("Standard")
    {:ok, view, _html} = live(conn, "/")

    render_click(view, "display_preferences_loaded", %{
      "enabled_techniques" => %{"bulk_buy" => false, "unknown_future_technique" => false},
      "enabled_categories" => %{"oils" => false, "unknown_future_category" => false},
      "sort_column" => "volume",
      "thresholds" => %{"margin" => "not-a-number", "profit" => 12}
    })

    # sort_column applies; the unrecognized technique/category keys are
    # ignored rather than crashing; bulk_buy's and oils's real, valid
    # entries still apply; the unparseable margin threshold is dropped, the
    # valid profit one isn't. exchange_spread wasn't mentioned in the
    # payload at all, so it keeps its default-enabled value (checked here
    # rather than vendor_recipe, since vendor_recipe's checkbox now lives
    # under the separate "Vendor Flip" tab, not the default active one).
    assert has_element?(view, "span.col-label.active", "Volume")
    refute has_element?(view, "input[aria-label='Bulk buy'][checked]")
    assert has_element?(view, "input[aria-label='Exchange spread'][checked]")

    view |> element("button.category-menu-toggle") |> render_click()
    refute has_element?(view, "[phx-value-category='oils'].category-item--selected")
    assert has_element?(view, "[phx-value-category='currency'].category-item--selected")
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
