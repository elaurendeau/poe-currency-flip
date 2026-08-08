defmodule PoeFlipFinder.FlipOpportunitiesTest do
  # async: false -- every test here activates a generation, which UPDATEs
  # the singleton exchange_ingestion_state row. See
  # EctoSnapshotRepositoryGatewayTest for why concurrent writers to that
  # one row deadlock against each other under the SQL Sandbox.
  use PoeFlipFinder.DataCase, async: false

  alias PoeFlipFinder.{BaseCurrencyIds, Currency, DivinationCardReward, FlipOpportunities}
  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.StubDivinationCardReferenceGateway

  # Context-level integration test per docs/ELIXIR_TEST_MANIFESTO.md: the
  # real Ecto-backed gateway against real DB rows, not a mock -- these are
  # the merge/orchestration use cases from
  # ComputeFlipOpportunitiesInteractorTest that don't belong to either
  # finder alone.

  # DivineChaosRate/the anchor logic key off the real GGG path constants,
  # not an arbitrary external_id -- unlike the other fixtures in this file
  # (Wisdom, Deck), Chaos and Divine must use the real ones.
  defp chaos_external_id, do: BaseCurrencyIds.chaos_external_id()
  defp divine_external_id, do: BaseCurrencyIds.divine_external_id()

  defp insert_currency!(external_id, display_name \\ nil, item_type \\ :currency) do
    %Schema.Currency{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: display_name || external_id,
      item_type: item_type
    )
    |> Repo.insert!()
  end

  defp insert_league!(external_id) do
    %Schema.League{}
    |> Ecto.Changeset.change(
      external_id: external_id,
      display_name: external_id,
      known_to_ggg: true
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

  test "merges exchange spread and bulk buy into one list" do
    # Chaos<->Divine reference (chaos_per_divine=210), an Exchange Spread
    # pair (chaos-wisdom), and a Bulk Buy candidate (deck trading against
    # both chaos and divine) -- all three techniques' worth of data
    # feeding one league, proving the merge wiring rather than just each
    # piece in isolation.
    league = insert_league!("Standard")
    chaos = insert_currency!(chaos_external_id())
    divine = insert_currency!(divine_external_id())
    wisdom = insert_currency!("Wisdom")
    deck = insert_currency!("Deck")

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
      lowest_ratio_b: 185.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 366.0
    })

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: deck.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 8.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 13.0
    })

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: divine.id,
      currency_b_id: deck.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 1700.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 1900.0
    })

    activate_generation!(1)

    opportunities = FlipOpportunities.compute_flip_opportunities("Standard")
    techniques = Enum.map(opportunities, & &1.technique)

    assert :exchange_spread in techniques
    assert :bulk_buy in techniques
    assert Enum.count(opportunities, &(&1.technique == :bulk_buy)) == 2
  end

  test "no chaos/divine rate: bulk buy contributes nothing but exchange spread still works" do
    league = insert_league!("Standard")
    chaos = insert_currency!(chaos_external_id())
    wisdom = insert_currency!("Wisdom")
    deck = insert_currency!("Deck")

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

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: deck.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 8.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 13.0
    })

    activate_generation!(1)

    opportunities = FlipOpportunities.compute_flip_opportunities("Standard")

    assert Enum.map(opportunities, & &1.technique) |> Enum.uniq() == [:exchange_spread]
  end

  test "zero volume exchange spread is excluded" do
    league = insert_league!("Standard")
    chaos = insert_currency!(chaos_external_id())
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
      # The buy leg's stock (highest_stock_a, since 366 is the higher
      # extreme) driven to 0 -- a pair nobody can actually trade against
      # isn't a real opportunity, no matter how attractive its margin
      # looks.
      highest_stock_a: 0
    })

    activate_generation!(1)

    assert FlipOpportunities.compute_flip_opportunities("Standard") == []
  end

  test "zero volume bulk buy leg excludes both directions" do
    league = insert_league!("Standard")
    chaos = insert_currency!(chaos_external_id())
    divine = insert_currency!(divine_external_id())
    deck = insert_currency!("Deck")

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
      currency_b_id: deck.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 8.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 13.0,
      # Chaos-deck leg's buy-side stock (highest_stock_a, the 13 extreme)
      # is 0 -- both Bulk Buy directions price this leg off that same
      # extreme, so both directions are bottlenecked by the same,
      # now-zero, stock figure.
      highest_stock_a: 0
    })

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: divine.id,
      currency_b_id: deck.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 1700.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 1900.0
    })

    activate_generation!(1)

    opportunities = FlipOpportunities.compute_flip_opportunities("Standard")

    refute Enum.any?(opportunities, &(&1.technique == :bulk_buy))
  end

  test "merges divination card into the list, sourced from a stubbed reference gateway" do
    Application.put_env(:poe_flip_finder, :divination_card_reference_gateway, StubDivinationCardReferenceGateway)
    on_exit(fn -> Application.delete_env(:poe_flip_finder, :divination_card_reference_gateway) end)

    league = insert_league!("Standard")
    chaos = insert_currency!(chaos_external_id())
    divine = insert_currency!(divine_external_id())
    card = insert_currency!("Metadata/Items/DivinationCards/DivinationCardTest", "Test Card", :divination_card)
    reward = insert_currency!("Metadata/Items/Currency/CurrencyTestReward", "Test Reward")

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
      currency_b_id: card.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 5.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 5.0
    })

    insert_snapshot!(%{
      generation_id: 1,
      league_id: league.id,
      currency_a_id: chaos.id,
      currency_b_id: reward.id,
      lowest_ratio_a: 1.0,
      lowest_ratio_b: 2.0,
      highest_ratio_a: 1.0,
      highest_ratio_b: 2.0
    })

    StubDivinationCardReferenceGateway.stub([
      %DivinationCardReward{
        card: %Currency{external_id: nil, display_name: "Test Card", item_type: :divination_card},
        stack_size: 8,
        reward_currency: %Currency{external_id: nil, display_name: "Test Reward", item_type: :currency},
        reward_quantity: 5,
        predictable: true
      }
    ])

    activate_generation!(1)

    opportunities = FlipOpportunities.compute_flip_opportunities("Standard")
    techniques = Enum.map(opportunities, & &1.technique)

    assert :divination_card in techniques
  end
end
