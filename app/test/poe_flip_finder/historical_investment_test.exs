defmodule PoeFlipFinder.HistoricalInvestmentTest do
  # async: false -- activates a generation, touching the singleton
  # exchange_ingestion_state row (see EctoSnapshotRepositoryGatewayTest for
  # why concurrent writers to that one row deadlock under the SQL Sandbox).
  use PoeFlipFinder.DataCase, async: false

  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.HistoricalPricePattern.{DayPrice, LeagueObservation}

  alias PoeFlipFinder.{
    BaseCurrencyIds,
    Currency,
    HistoricalInvestment,
    HistoricalPricePattern,
    League
  }

  alias PoeFlipFinder.{StubClock, StubHistoricalPatternReferenceGateway}

  # Context-level integration test per docs/ELIXIR_TEST_MANIFESTO.md: the
  # real Ecto-backed snapshot gateway against real DB rows for the live
  # cross-check half; a stub reference gateway (one-layer-up substitution)
  # for the historical-pattern half, so the ranking math is tested against
  # known values rather than the real bundled catalog's real numbers
  # (that's BundledHistoricalPatternReferenceGatewayTest's job).

  setup do
    Application.put_env(:poe_flip_finder, :clock, StubClock)

    Application.put_env(
      :poe_flip_finder,
      :historical_pattern_reference_gateway,
      StubHistoricalPatternReferenceGateway
    )

    on_exit(fn ->
      Application.delete_env(:poe_flip_finder, :clock)
      Application.delete_env(:poe_flip_finder, :historical_pattern_reference_gateway)
    end)

    :ok
  end

  defp insert_currency!(external_id, display_name \\ nil, category \\ :currency) do
    %Schema.Currency{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: display_name || external_id,
      category: category
    )
    |> Repo.insert!()
  end

  defp insert_league!(external_id, start_at) do
    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: external_id,
      known_to_ggg: true,
      start_at: start_at
    )
    |> Repo.insert!()
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
    |> Repo.insert!()
  end

  defp activate_generation!(generation_id) do
    Repo.get!(Schema.ExchangeIngestionState, 1)
    |> Ecto.Changeset.change(active_generation_id: generation_id, updated_at: DateTime.utc_now())
    |> Repo.update!()
  end

  defp league_entity(schema) do
    %League{
      id: schema.id,
      external_id: schema.external_id,
      display_name: schema.display_name,
      is_current: schema.is_current,
      has_exchange_activity: schema.has_exchange_activity,
      start_at: schema.start_at
    }
  end

  # `observations` is a list of {league_name, [{day, chaos}, ...]} tuples,
  # in most-recent-league-first order -- the same convention the real
  # bundled reference data is authored in, per HistoricalInvestment's
  # moduledoc ("last league" == List.first/1).
  defp pattern(currency_name, category, observations) do
    %HistoricalPricePattern{
      currency: %Currency{
        id: nil,
        external_id: nil,
        display_name: currency_name,
        icon_url: nil,
        category: category
      },
      league_observations:
        Enum.map(observations, fn {league, days} -> observation(league, days) end)
    }
  end

  defp observation(league, day_chaos_pairs) do
    %LeagueObservation{
      league: league,
      day_prices:
        Enum.map(day_chaos_pairs, fn {day, chaos} -> %DayPrice{day: day, chaos: chaos * 1.0} end)
    }
  end

  describe "max_sampled_day/0" do
    test "is the deepest real day in each pattern's LAST (most recent) league only" do
      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [{"Necropolis", [{0, 3}, {1, 9}]}]),
        # Affliction (older, listed second) reaches day 20, but it isn't
        # the last league for this pattern -- Necropolis's day 6 is what
        # should count, per docs/PRD.md § 7.14's "last league" rule.
        pattern("Farrul, First of the Plains", :beasts, [
          {"Necropolis", [{0, 1}, {6, 2}]},
          {"Affliction", [{0, 1}, {20, 5}]}
        ])
      ])

      assert HistoricalInvestment.max_sampled_day() == 6
    end

    test "is nil when there are no patterns at all" do
      StubHistoricalPatternReferenceGateway.stub([])

      assert HistoricalInvestment.max_sampled_day() == nil
    end
  end

  describe "current_league_elapsed/1" do
    test "splits real elapsed time into days and the hour-of-day remainder" do
      StubClock.stub(~U[2026-08-09 14:00:00Z])

      league = %League{
        external_id: "Necropolis",
        display_name: "Necropolis",
        is_current: true,
        has_exchange_activity: true,
        start_at: ~U[2026-08-07 12:00:00Z]
      }

      # 2 days and 2 hours have really elapsed (Aug 7 12:00 -> Aug 9 14:00).
      assert HistoricalInvestment.current_league_elapsed(league) ==
               {:ok, %{days: 2, hours_into_day: 2}}
    end

    test "is :unknown when start_at was never captured" do
      league = %League{
        external_id: "Necropolis",
        display_name: "Necropolis",
        is_current: true,
        has_exchange_activity: true,
        start_at: nil
      }

      assert HistoricalInvestment.current_league_elapsed(league) == :unknown
    end
  end

  describe "current_league_day/1" do
    test "computes the real elapsed day count from start_at" do
      StubClock.stub(~U[2026-08-09 12:00:00Z])

      league = %League{
        external_id: "Necropolis",
        display_name: "Necropolis",
        is_current: true,
        has_exchange_activity: true,
        start_at: ~U[2026-08-07 12:00:00Z]
      }

      assert HistoricalInvestment.current_league_day(league) == {:ok, 2}
    end

    test "is :unknown when start_at was never captured" do
      league = %League{
        external_id: "Necropolis",
        display_name: "Necropolis",
        is_current: true,
        has_exchange_activity: true,
        start_at: nil
      }

      assert HistoricalInvestment.current_league_day(league) == :unknown
    end

    test "is :unknown rather than a negative day, if start_at is somehow in the future" do
      StubClock.stub(~U[2026-08-07 00:00:00Z])

      league = %League{
        external_id: "Necropolis",
        display_name: "Necropolis",
        is_current: true,
        has_exchange_activity: true,
        start_at: ~U[2026-08-09 00:00:00Z]
      }

      assert HistoricalInvestment.current_league_day(league) == :unknown
    end
  end

  describe "compute_candidates/1" do
    test "builds a candidate from the LAST league only, with all four horizons" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [
          {"Necropolis", [{0, 3}, {1, 9}, {3, 15}, {7, 30}, {14, 60}]}
        ])
      ])

      {:ok, [candidate]} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      assert candidate.league == "Necropolis"
      assert candidate.today_day == 0
      assert candidate.today_chaos == 3.0

      assert candidate.horizons.day_1 == %{days: 1, chaos: 9.0, gain_pct: 200.0}
      assert candidate.horizons.day_3 == %{days: 3, chaos: 15.0, gain_pct: 400.0}
      assert candidate.horizons.week_1 == %{days: 7, chaos: 30.0, gain_pct: 900.0}
      assert candidate.horizons.week_2 == %{days: 14, chaos: 60.0, gain_pct: 1900.0}

      assert candidate.trajectory ==
               observation("Necropolis", [{0, 3}, {1, 9}, {3, 15}, {7, 30}, {14, 60}]).day_prices
    end

    test "a horizon with no real data at that offset is nil, never fabricated" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        # Only reaches day 3 -- week_1/week_2 have nothing to report.
        pattern("Exalted Orb", :currency, [{"Necropolis", [{0, 3}, {1, 9}, {3, 15}]}])
      ])

      {:ok, [candidate]} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      assert candidate.horizons.day_1 != nil
      assert candidate.horizons.day_3 != nil
      assert candidate.horizons.week_1 == nil
      assert candidate.horizons.week_2 == nil
    end

    test "excludes a pattern whose LAST league has no price at today, even if an older league does" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [
          {"Necropolis", [{5, 20}, {6, 25}]},
          {"Affliction", [{0, 3}, {1, 9}]}
        ])
      ])

      {:ok, candidates} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      assert candidates == []
    end

    test "is :unknown_league_start when the selected league's start_at was never captured" do
      league_schema = insert_league!("Private League", nil)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [{"Necropolis", [{0, 3}, {1, 9}]}])
      ])

      assert HistoricalInvestment.compute_candidates(league_entity(league_schema)) ==
               :unknown_league_start
    end
  end

  describe "sort_by_horizon/3" do
    # `chaos` is deliberately given the OPPOSITE ordering from `gain_pct`
    # in these fixtures -- if sort_by_horizon/3 ever regresses back to
    # ranking by raw chaos value (a real bug found via manual verification:
    # a 60,000c Mirror of Kalandra sorted first purely because it's an
    # expensive item, not because it was actually rising), these tests
    # would fail instead of silently passing on a coincidence.
    defp candidate_with_day_1(name, gain_pct_or_nil) do
      horizons =
        case gain_pct_or_nil do
          nil -> %{day_1: nil}
          gain_pct -> %{day_1: %{days: 1, chaos: 1000.0 - gain_pct, gain_pct: gain_pct}}
        end

      %{pattern: pattern(name, :currency, [{"Necropolis", [{0, 1}]}]), horizons: horizons}
    end

    test "sorts by gain %, not raw chaos value, descending by default" do
      candidates = [
        candidate_with_day_1("Low", 10.0),
        candidate_with_day_1("High", 100.0),
        candidate_with_day_1("Mid", 50.0)
      ]

      sorted = HistoricalInvestment.sort_by_horizon(candidates, :day_1)
      assert Enum.map(sorted, & &1.pattern.currency.display_name) == ["High", "Mid", "Low"]
    end

    test "ascending flips the order" do
      candidates = [candidate_with_day_1("Low", 10.0), candidate_with_day_1("High", 100.0)]

      sorted = HistoricalInvestment.sort_by_horizon(candidates, :day_1, :asc)
      assert Enum.map(sorted, & &1.pattern.currency.display_name) == ["Low", "High"]
    end

    test "a candidate with no data at that horizon sorts last, in either direction" do
      candidates = [
        candidate_with_day_1("NoData", nil),
        candidate_with_day_1("High", 100.0),
        candidate_with_day_1("Low", 10.0)
      ]

      assert HistoricalInvestment.sort_by_horizon(candidates, :day_1, :desc)
             |> Enum.map(& &1.pattern.currency.display_name) == ["High", "Low", "NoData"]

      assert HistoricalInvestment.sort_by_horizon(candidates, :day_1, :asc)
             |> Enum.map(& &1.pattern.currency.display_name) == ["Low", "High", "NoData"]
    end
  end

  describe "compute_candidates/1 live price cross-check" do
    test "resolves today's real live chaos price when the item is actively trading" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])
      chaos = insert_currency!(BaseCurrencyIds.chaos_external_id())
      exalted = insert_currency!("exalted-path", "Exalted Orb")

      insert_snapshot!(%{
        generation_id: 1,
        league_id: league_schema.id,
        currency_a_id: chaos.id,
        currency_b_id: exalted.id,
        lowest_ratio_a: 1.0,
        lowest_ratio_b: 4.0,
        highest_ratio_a: 1.0,
        highest_ratio_b: 3.0
      })

      activate_generation!(1)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [{"Necropolis", [{0, 3}, {1, 9}]}])
      ])

      {:ok, [candidate]} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      # (1/4 + 1/3) / 2 = 0.2917 chaos per Exalted Orb at the quoted extremes.
      assert {:ok, live_price} = candidate.live_price
      assert_in_delta live_price, 0.2917, 0.001
    end

    test "is :not_traded_this_refresh for a live-capable category with no matching snapshot" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])
      activate_generation!(1)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [{"Necropolis", [{0, 3}, {1, 9}]}])
      ])

      {:ok, [candidate]} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      assert candidate.live_price == :not_traded_this_refresh
    end

    test "a snapshot with a zero ratio is skipped, not a crash" do
      # Regression test: a real Allflame market snapshot with a zero ratio
      # on one side crashed the whole LiveView process with an
      # ArithmeticError (division by zero) during manual verification --
      # real production data, not a hypothetical edge case.
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])
      chaos = insert_currency!(BaseCurrencyIds.chaos_external_id())
      exalted = insert_currency!("exalted-path", "Exalted Orb")

      insert_snapshot!(%{
        generation_id: 1,
        league_id: league_schema.id,
        currency_a_id: chaos.id,
        currency_b_id: exalted.id,
        lowest_ratio_a: 1.0,
        lowest_ratio_b: 0.0,
        highest_ratio_a: 1.0,
        highest_ratio_b: 3.0
      })

      activate_generation!(1)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [{"Necropolis", [{0, 3}, {1, 9}]}])
      ])

      {:ok, [candidate]} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      assert candidate.live_price == :not_traded_this_refresh
    end

    test "is :no_live_market for a historical-only category (Cluster Jewels), even with matching snapshots" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])
      activate_generation!(1)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Large Cluster Jewel: 12% increased Fire Damage", :cluster_jewels, [
          {"Necropolis", [{0, 2.2}, {1, 10}]}
        ])
      ])

      {:ok, [candidate]} = HistoricalInvestment.compute_candidates(league_entity(league_schema))

      assert candidate.live_price == :no_live_market
    end
  end
end
