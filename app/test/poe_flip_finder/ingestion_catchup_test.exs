defmodule PoeFlipFinder.IngestionCatchupTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{
    CatchupCapPolicy,
    Currency,
    ExchangeChangeStreamPage,
    ExchangeMarketEntry,
    IngestionFreshness,
    League
  }

  alias PoeFlipFinder.{
    Ingestion,
    StubClock,
    StubCurrencyReferenceGateway,
    StubExchangeSourceGateway,
    StubLeagueReferenceGateway,
    StubSnapshotRepositoryGateway
  }

  # Ported 1:1 from RunIngestionCatchupInteractorTest -- already drilled and
  # confirmed traceable to docs/ARCHITECTURE.md § Currency Exchange
  # Ingestion (see docs/ELIXIR_TEST_MANIFESTO.md § Use-Case Discovery). Two
  # cases (unresolvable-pair distinct-count, same-pair-across-hours dedup)
  # were undocumented gaps found while drilling -- added to ARCHITECTURE.md
  # rather than silently porting undocumented behavior.

  @now ~U[2026-08-06 12:00:00Z]
  @current_hour div(DateTime.to_unix(@now), 3600) * 3600

  @currency_a %Currency{id: 1, external_id: "A", display_name: "Currency A", category: :currency}
  @currency_b %Currency{id: 2, external_id: "B", display_name: "Currency B", category: :currency}
  @league %League{
    id: 1,
    external_id: "Standard",
    display_name: "Standard",
    is_current: false,
    has_exchange_activity: true
  }

  setup do
    Application.put_env(:poe_flip_finder, :exchange_source_gateway, StubExchangeSourceGateway)

    Application.put_env(
      :poe_flip_finder,
      :currency_reference_gateway,
      StubCurrencyReferenceGateway
    )

    Application.put_env(:poe_flip_finder, :league_reference_gateway, StubLeagueReferenceGateway)

    Application.put_env(
      :poe_flip_finder,
      :snapshot_repository_gateway,
      StubSnapshotRepositoryGateway
    )

    Application.put_env(:poe_flip_finder, :clock, StubClock)
    StubClock.stub(@now)

    on_exit(fn ->
      Enum.each(
        [
          :exchange_source_gateway,
          :currency_reference_gateway,
          :league_reference_gateway,
          :snapshot_repository_gateway,
          :clock
        ],
        &Application.delete_env(:poe_flip_finder, &1)
      )
    end)

    :ok
  end

  defp one_entry do
    %ExchangeMarketEntry{
      league_external_id: "Standard",
      currency_a_external_id: "A",
      currency_b_external_id: "B",
      snapshot_hour: @now,
      volume_traded_a: 1,
      volume_traded_b: 2,
      lowest_stock_a: 3,
      highest_stock_a: 4,
      lowest_stock_b: 5,
      highest_stock_b: 6,
      lowest_ratio_a: 1.0,
      highest_ratio_a: 2.0,
      lowest_ratio_b: 3.0,
      highest_ratio_b: 4.0
    }
  end

  defp page(entries, next_change_id, at_tip),
    do: %ExchangeChangeStreamPage{
      entries: entries,
      next_change_id: next_change_id,
      at_tip: at_tip
    }

  test "reaches tip before the cap: reports fully caught up and commits" do
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)
    StubExchangeSourceGateway.stub(1000, {:ok, page([one_entry()], 2000, false)})
    StubExchangeSourceGateway.stub(2000, {:ok, page([], 2000, true)})
    StubCurrencyReferenceGateway.stub("A", @currency_a)
    StubCurrencyReferenceGateway.stub("B", @currency_b)
    StubLeagueReferenceGateway.stub("Standard", @league)

    {:ok, result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })

    assert result.hours_processed == 1
    assert result.fully_caught_up == true
    assert result.last_processed_change_id == 2000
    assert result.skipped_unresolvable_market_entry_count == 0
    assert {:commit_generation, 999, 2000} in StubSnapshotRepositoryGateway.calls()
    refute Enum.any?(StubSnapshotRepositoryGateway.calls(), &match?({:discard_generation, _}, &1))
  end

  test "hits the hour cap: reports partial progress but still commits and advances the checkpoint" do
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)
    # Never returns at_tip -- always another hour available.
    StubExchangeSourceGateway.stub_computed(fn requested ->
      {:ok, page([one_entry()], requested + 3600, false)}
    end)

    StubCurrencyReferenceGateway.stub("A", @currency_a)
    StubCurrencyReferenceGateway.stub("B", @currency_b)
    StubLeagueReferenceGateway.stub("Standard", @league)

    {:ok, result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 3,
        first_run_lookback_hours: 24
      })

    expected_last_processed = 1000 + 3 * 3600
    assert result.hours_processed == 3
    assert result.fully_caught_up == false
    assert result.last_processed_change_id == expected_last_processed

    assert {:commit_generation, 999, expected_last_processed} in StubSnapshotRepositoryGateway.calls()
  end

  test "unresolvable currency skips that pair, continues the run, reports the skipped count" do
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)
    StubExchangeSourceGateway.stub(1000, {:ok, page([one_entry()], 2000, false)})
    StubExchangeSourceGateway.stub(2000, {:ok, page([], 2000, true)})
    # Currency A is unresolvable -- currency B and league are never even
    # looked up, since resolution short-circuits on the first failure.
    StubCurrencyReferenceGateway.stub("A", nil)

    {:ok, result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })

    assert {:save_snapshots, []} in StubSnapshotRepositoryGateway.calls()
    assert result.hours_processed == 1
    assert result.last_processed_change_id == 2000
    assert result.skipped_unresolvable_market_entry_count == 1
  end

  test "the same unresolvable pair across multiple hours counts once, not once per hour" do
    # Regression test: reported skip count must reflect distinct
    # unresolvable pairs, not raw per-hour occurrences -- confirmed
    # against real GGG data that the same unresolvable pair recurs in
    # most hours it's active, which had inflated this count massively
    # under a naive per-occurrence tally. See docs/ARCHITECTURE.md's
    # ingestion section (added while drilling this port).
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)
    StubExchangeSourceGateway.stub(1000, {:ok, page([one_entry()], 2000, false)})
    StubExchangeSourceGateway.stub(2000, {:ok, page([one_entry()], 3000, false)})
    StubExchangeSourceGateway.stub(3000, {:ok, page([], 3000, true)})
    StubCurrencyReferenceGateway.stub("A", nil)

    {:ok, result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })

    assert result.hours_processed == 2
    assert result.last_processed_change_id == 3000
    assert result.skipped_unresolvable_market_entry_count == 1
  end

  test "a hard failure mid-walk discards the generation and propagates the error, checkpoint unchanged" do
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)
    # First hour succeeds (so a generation actually gets minted) -- the
    # failure must happen on a later hour to be "mid walk".
    StubExchangeSourceGateway.stub(1000, {:ok, page([one_entry()], 2000, false)})
    StubExchangeSourceGateway.stub(2000, {:error, :network_exploded})
    StubCurrencyReferenceGateway.stub("A", @currency_a)
    StubCurrencyReferenceGateway.stub("B", @currency_b)
    StubLeagueReferenceGateway.stub("Standard", @league)

    assert {:error, :network_exploded} =
             Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
               max_hours_per_call: 48,
               first_run_lookback_hours: 24
             })

    assert {:discard_generation, 999} in StubSnapshotRepositoryGateway.calls()

    refute Enum.any?(
             StubSnapshotRepositoryGateway.calls(),
             &match?({:commit_generation, _, _}, &1)
           )
  end

  test "already caught up is a no-op: never touches the active generation" do
    # Regression test: a refresh call that immediately finds nothing new
    # must not mint/commit an empty generation -- doing so purged the
    # still-good active generation for zero gain against real GGG data
    # (docs/ARCHITECTURE.md § Failure Handling: never replace
    # last-known-good data with worse data).
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 5000,
      active_generation_refreshed_at: ~U[2026-08-06 00:00:00Z]
    })

    StubExchangeSourceGateway.stub(5000, {:ok, page([], 5000, true)})

    {:ok, result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })

    assert result == %PoeFlipFinder.CatchupResult{
             hours_processed: 0,
             fully_caught_up: true,
             last_processed_change_id: 5000,
             skipped_unresolvable_market_entry_count: 0
           }

    refute Enum.any?(
             StubSnapshotRepositoryGateway.calls(),
             &match?({:commit_generation, _, _}, &1)
           )

    refute Enum.any?(StubSnapshotRepositoryGateway.calls(), &match?({:discard_generation, _}, &1))
    refute Enum.any?(StubSnapshotRepositoryGateway.calls(), &match?({:save_snapshots, _}, &1))
  end

  test "the same currency pair across multiple hours saves only the latest occurrence" do
    # Regression test: exchange_market_snapshot's unique constraint is one
    # row per pair *per generation* (docs/SCHEMA.md), but the same pair
    # routinely reappears across many hours of one walk. Saving per-hour
    # without deduplication hit a real duplicate-key failure against live
    # GGG data.
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)

    earlier_hour_entry = %{one_entry() | volume_traded_a: 1}
    later_hour_entry = %{one_entry() | volume_traded_a: 99}

    StubExchangeSourceGateway.stub(1000, {:ok, page([earlier_hour_entry], 2000, false)})
    StubExchangeSourceGateway.stub(2000, {:ok, page([later_hour_entry], 3000, false)})
    StubExchangeSourceGateway.stub(3000, {:ok, page([], 3000, true)})
    StubCurrencyReferenceGateway.stub("A", @currency_a)
    StubCurrencyReferenceGateway.stub("B", @currency_b)
    StubLeagueReferenceGateway.stub("Standard", @league)

    {:ok, _result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })

    [{:save_snapshots, saved}] =
      Enum.filter(StubSnapshotRepositoryGateway.calls(), &match?({:save_snapshots, _}, &1))

    assert length(saved) == 1
    assert hd(saved).volume_traded_a == 99
  end

  test "no stored checkpoint: seeds from the lookback window, not from GGG's launch" do
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: nil,
      active_generation_refreshed_at: nil
    })

    expected_start = @current_hour - 24 * 3600
    StubExchangeSourceGateway.stub(expected_start, {:ok, page([], expected_start, true)})

    {:ok, result} =
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })

    # Immediately at tip from that computed starting point, so this is
    # also a no-op -- proves the lookback math without needing any hour
    # to actually contain data.
    assert result.last_processed_change_id == expected_start
    refute Enum.any?(StubSnapshotRepositoryGateway.calls(), &match?({:save_snapshots, _}, &1))
  end

  test "discard_generation itself also failing surfaces loudly rather than swallowing the original failure" do
    # Adapted from the Java version's exception-suppression regression test
    # (production once surfaced only the cleanup failure, silently losing
    # the real fetch/normalize failure that triggered it -- a missing
    # @Transactional on the gateway). Elixir has no exception-suppression
    # mechanism to replicate directly: errors here are values
    # ({:error, reason}), not exceptions, until something genuinely
    # crashes. The equivalent guarantee is: cleanup is still *attempted*
    # (proving the original failure wasn't silently dropped before even
    # trying to discard), and if cleanup itself crashes, that crash
    # propagates loudly rather than being caught and hidden.
    StubSnapshotRepositoryGateway.stub_ingestion_state(%IngestionFreshness{
      last_processed_change_id: 1000,
      active_generation_refreshed_at: nil
    })

    StubSnapshotRepositoryGateway.stub_new_generation(999)
    StubExchangeSourceGateway.stub(1000, {:ok, page([one_entry()], 2000, false)})
    StubExchangeSourceGateway.stub(2000, {:error, :network_exploded})
    StubCurrencyReferenceGateway.stub("A", @currency_a)
    StubCurrencyReferenceGateway.stub("B", @currency_b)
    StubLeagueReferenceGateway.stub("Standard", @league)

    StubSnapshotRepositoryGateway.stub_discard_generation_raises(fn ->
      raise "discard also failed"
    end)

    assert_raise RuntimeError, "discard also failed", fn ->
      Ingestion.run_ingestion_catchup(%CatchupCapPolicy{
        max_hours_per_call: 48,
        first_run_lookback_hours: 24
      })
    end

    # The discard was attempted despite ultimately raising -- the original
    # fetch failure wasn't dropped before cleanup was even tried.
    assert {:discard_generation, 999} in StubSnapshotRepositoryGateway.calls()
  end
end
