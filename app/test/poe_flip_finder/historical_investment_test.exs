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

  defp pattern(currency_name, category, observations) do
    %HistoricalPricePattern{
      currency: %Currency{
        id: nil,
        external_id: nil,
        display_name: currency_name,
        icon_url: nil,
        category: category
      },
      league_observations: observations
    }
  end

  defp observation(league, day_chaos_pairs) do
    %LeagueObservation{
      league: league,
      day_prices:
        Enum.map(day_chaos_pairs, fn {day, chaos} -> %DayPrice{day: day, chaos: chaos * 1.0} end)
    }
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

  describe "compute_candidates/2" do
    test "ranks by best observed gain %, using only real day/day+1 evidence" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [
          observation("Necropolis", [{0, 3}, {1, 9}, {2, 10.74}])
        ]),
        pattern("Chromatic Orb", :currency, [
          observation("Necropolis", [{0, 0.09}, {1, 0.17}, {2, 0.17}])
        ])
      ])

      {:ok, [top, second]} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      assert top.pattern.currency.display_name == "Exalted Orb"
      [evidence] = top.league_evidence
      assert evidence.day_chaos == 3.0
      assert evidence.next_day_chaos == 9.0
      assert_in_delta evidence.gain_pct, 200.0, 0.001
      assert evidence.units == 13
      assert evidence.affordable == true
      assert_in_delta evidence.projected_value_chaos, 117.0, 0.001

      assert second.pattern.currency.display_name == "Chromatic Orb"
    end

    test "excludes a pattern with no league observation covering both the current day and the next" do
      StubClock.stub(~U[2026-08-15 00:00:00Z])
      # Day 6 -- the fixture data below only reaches day 2.
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [
          observation("Necropolis", [{0, 3}, {1, 9}, {2, 10.74}])
        ])
      ])

      {:ok, candidates} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      assert candidates == []
    end

    test "an amount that can't afford even 1 unit still shows as evidence, just not affordable" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Awakener's Orb", :currency, [
          observation("Necropolis", [{0, 61.6}, {1, 97.2}])
        ])
      ])

      {:ok, [candidate]} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      [evidence] = candidate.league_evidence

      assert evidence.units == 0
      assert evidence.affordable == false
      assert evidence.projected_value_chaos == nil
      # gain_pct is still real, known evidence even though it's unaffordable right now.
      assert_in_delta evidence.gain_pct, 57.79, 0.01
    end

    test "confidence counts how many sampled leagues have evidence, and how many actually rose" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Ancestor", ~U[2026-08-09 00:00:00Z])

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Orb of Annulment", :currency, [
          observation("Necropolis", [{0, 3}, {1, 4}]),
          observation("Affliction", [{0, 2.7}, {1, 5}]),
          observation("Ancestor", [{0, 8.8}, {1, 6}])
        ])
      ])

      {:ok, [candidate]} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      assert candidate.confidence_total == 3
      # Ancestor's own observation dropped (8.8 -> 6), so only 2 of the 3 rose.
      assert candidate.confidence_rising == 2
    end

    test "is :unknown_league_start when the selected league's start_at was never captured" do
      league_schema = insert_league!("Private League", nil)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [observation("Necropolis", [{0, 3}, {1, 9}])])
      ])

      assert HistoricalInvestment.compute_candidates(league_entity(league_schema), 40) ==
               :unknown_league_start
    end
  end

  describe "compute_candidates/2 live price cross-check" do
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
        pattern("Exalted Orb", :currency, [observation("Necropolis", [{0, 3}, {1, 9}])])
      ])

      {:ok, [candidate]} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      # (1/4 + 1/3) / 2 = 0.2917 chaos per Exalted Orb at the quoted extremes.
      assert {:ok, live_price} = candidate.live_price
      assert_in_delta live_price, 0.2917, 0.001
    end

    test "is :not_traded_this_refresh for a live-capable category with no matching snapshot" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])
      activate_generation!(1)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Exalted Orb", :currency, [observation("Necropolis", [{0, 3}, {1, 9}])])
      ])

      {:ok, [candidate]} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      assert candidate.live_price == :not_traded_this_refresh
    end

    test "is :no_live_market for a historical-only category (Cluster Jewels), even with matching snapshots" do
      StubClock.stub(~U[2026-08-09 00:00:00Z])
      league_schema = insert_league!("Necropolis", ~U[2026-08-09 00:00:00Z])
      activate_generation!(1)

      StubHistoricalPatternReferenceGateway.stub([
        pattern("Large Cluster Jewel: 12% increased Fire Damage", :cluster_jewels, [
          observation("Necropolis", [{0, 2.2}, {1, 10}])
        ])
      ])

      {:ok, [candidate]} =
        HistoricalInvestment.compute_candidates(league_entity(league_schema), 40)

      assert candidate.live_price == :no_live_market
    end
  end
end
