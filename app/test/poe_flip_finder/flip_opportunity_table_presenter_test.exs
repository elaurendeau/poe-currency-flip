defmodule PoeFlipFinder.FlipOpportunityTablePresenterTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{Currency, CurrencyAmount, FlipOpportunity, FlipOpportunityTablePresenter}

  # Ported 1:1 from flipOpportunityTablePresenter.test.ts.

  defp currency_amount(external_id, display_name, quantity, category \\ :currency) do
    %CurrencyAmount{
      currency: %Currency{
        id: nil,
        external_id: external_id,
        display_name: display_name,
        category: category
      },
      quantity: quantity
    }
  end

  defp chaos_profit(quantity), do: currency_amount("chaos", "Chaos Orb", quantity)

  defp opportunity(overrides \\ %{}) do
    Map.merge(
      %FlipOpportunity{
        technique: :exchange_spread,
        start: [currency_amount("chaos", "Chaos Orb", 1)],
        via: [currency_amount("wisdom", "Scroll of Wisdom", 366)],
        sell: [currency_amount("chaos", "Chaos Orb", 1.9784)],
        margin_percent: 97.84,
        profit: chaos_profit(0.9784),
        start_chaos_equivalent: 1.0,
        volume: 1234,
        detail: "buy 365:1 · sell 186:1"
      },
      overrides
    )
  end

  @all_enabled %{
    vendor_recipe: true,
    exchange_spread: true,
    divination_card: true,
    bulk_buy: true
  }

  @all_categories [
    :cards,
    :fragments,
    :ancestor,
    :essences,
    :currency,
    :beasts,
    :map_key,
    :heist,
    :runegrafts,
    :delve,
    :sanctum,
    :maps_unique,
    :delirium_orbs,
    :oils,
    :catalysts,
    :ducats,
    :maps_special,
    :allflame_embers,
    :keepers,
    :enshrouding_crystals,
    :legacy,
    :expedition,
    :misc
  ]

  @all_categories_enabled Map.new(@all_categories, &{&1, true})

  describe "get_route_key/1" do
    test "is identical for two opportunities with the same technique and currencies" do
      a = opportunity()
      b = opportunity(%{margin_percent: 12, profit: chaos_profit(0.1), volume: 5})

      assert FlipOpportunityTablePresenter.get_route_key(a) ==
               FlipOpportunityTablePresenter.get_route_key(b)
    end

    test "differs when the technique differs" do
      a = opportunity(%{technique: :exchange_spread})
      b = opportunity(%{technique: :bulk_buy})

      refute FlipOpportunityTablePresenter.get_route_key(a) ==
               FlipOpportunityTablePresenter.get_route_key(b)
    end

    test "differs when the via currency differs" do
      a = opportunity()
      b = opportunity(%{via: [currency_amount("portal", "Portal Scroll", 10)]})

      refute FlipOpportunityTablePresenter.get_route_key(a) ==
               FlipOpportunityTablePresenter.get_route_key(b)
    end
  end

  describe "filter_by_technique/2" do
    test "keeps only opportunities whose technique is enabled" do
      spread = opportunity(%{technique: :exchange_spread})
      bulk = opportunity(%{technique: :bulk_buy})

      result =
        FlipOpportunityTablePresenter.filter_by_technique([spread, bulk], %{
          @all_enabled
          | bulk_buy: false
        })

      assert result == [spread]
    end
  end

  describe "filter_by_category/2" do
    test "keeps every opportunity when every category is enabled (default)" do
      currency =
        opportunity(%{via: [currency_amount("wisdom", "Scroll of Wisdom", 1, :currency)]})

      oil = opportunity(%{via: [currency_amount("oil", "Golden Oil", 1, :oils)]})

      result =
        FlipOpportunityTablePresenter.filter_by_category([currency, oil], @all_categories_enabled)

      assert result == [currency, oil]
    end

    test "hides opportunities whose Via category is disabled" do
      currency =
        opportunity(%{via: [currency_amount("wisdom", "Scroll of Wisdom", 1, :currency)]})

      oil = opportunity(%{via: [currency_amount("oil", "Golden Oil", 1, :oils)]})

      result =
        FlipOpportunityTablePresenter.filter_by_category(
          [currency, oil],
          %{@all_categories_enabled | oils: false}
        )

      assert result == [currency]
    end

    test "a Divination Card opportunity is categorized by the reward it gives, not the card itself" do
      # Via is [card, reward] for :divination_card (see
      # DivinationCardOpportunityFinder) -- the card leg is always :cards
      # and would be a useless filter dimension, so the category that must
      # drive filtering is the reward (the second/last Via leg).
      card_for_oil =
        opportunity(%{
          technique: :divination_card,
          via: [
            currency_amount("card", "The Doctor", 5, :cards),
            currency_amount("oil", "Golden Oil", 1, :oils)
          ]
        })

      # Disabling :cards (the card's own category) must NOT hide this row --
      # only disabling the reward's category (:oils) should.
      result_cards_disabled =
        FlipOpportunityTablePresenter.filter_by_category(
          [card_for_oil],
          %{@all_categories_enabled | cards: false}
        )

      assert result_cards_disabled == [card_for_oil]

      result_oils_disabled =
        FlipOpportunityTablePresenter.filter_by_category(
          [card_for_oil],
          %{@all_categories_enabled | oils: false}
        )

      assert result_oils_disabled == []
    end
  end

  describe "filter_by_thresholds/2" do
    test "keeps opportunities at or above every provided threshold" do
      low = opportunity(%{margin_percent: 10, volume: 5})
      high = opportunity(%{margin_percent: 90, volume: 500})

      assert FlipOpportunityTablePresenter.filter_by_thresholds([low, high], %{margin: 50}) == [
               high
             ]

      assert FlipOpportunityTablePresenter.filter_by_thresholds([low, high], %{volume: 5}) == [
               low,
               high
             ]
    end

    test "applies multiple thresholds together" do
      meets_margin_only = opportunity(%{margin_percent: 90, volume: 1})
      meets_both = opportunity(%{margin_percent: 90, volume: 100})

      result =
        FlipOpportunityTablePresenter.filter_by_thresholds([meets_margin_only, meets_both], %{
          margin: 50,
          volume: 50
        })

      assert result == [meets_both]
    end

    test "returns everything when no thresholds are provided" do
      items = [opportunity(), opportunity(%{margin_percent: 1})]

      assert FlipOpportunityTablePresenter.filter_by_thresholds(items, %{}) == items
    end
  end

  describe "filter_by_max_start_chaos/2" do
    test "passes everything through when nil" do
      items = [
        opportunity(%{start_chaos_equivalent: 1.0}),
        opportunity(%{start_chaos_equivalent: 500.0})
      ]

      assert FlipOpportunityTablePresenter.filter_by_max_start_chaos(items, nil) == items
    end

    test "keeps rows at or under the cap regardless of anchor currency, using the Chaos-normalized value" do
      cheap = opportunity(%{start_chaos_equivalent: 5.0})

      divine_anchored_but_affordable =
        opportunity(%{
          start: [currency_amount("divine", "Divine Orb", 0.05)],
          start_chaos_equivalent: 8.0
        })

      too_expensive = opportunity(%{start_chaos_equivalent: 79.0})

      result =
        FlipOpportunityTablePresenter.filter_by_max_start_chaos(
          [cheap, divine_anchored_but_affordable, too_expensive],
          10.0
        )

      assert result == [cheap, divine_anchored_but_affordable]
    end
  end

  describe "sort_opportunities/3" do
    test "sorts ascending by the requested column" do
      low = opportunity(%{profit: chaos_profit(1)})
      high = opportunity(%{profit: chaos_profit(9)})

      assert FlipOpportunityTablePresenter.sort_opportunities([high, low], :profit, :asc) == [
               low,
               high
             ]
    end

    test "sorts descending by the requested column" do
      low = opportunity(%{volume: 1})
      high = opportunity(%{volume: 9})

      assert FlipOpportunityTablePresenter.sort_opportunities([low, high], :volume, :desc) == [
               high,
               low
             ]
    end

    test "does not mutate the input list" do
      items = [opportunity(%{margin_percent: 1}), opportunity(%{margin_percent: 9})]
      original = items

      FlipOpportunityTablePresenter.sort_opportunities(items, :margin, :desc)

      assert items == original
    end
  end

  describe "partition_favorites/2" do
    test "splits opportunities into favorites and others by route key" do
      favorited = opportunity(%{technique: :exchange_spread})
      not_favorited = opportunity(%{technique: :bulk_buy})

      result =
        FlipOpportunityTablePresenter.partition_favorites(
          [favorited, not_favorited],
          MapSet.new([FlipOpportunityTablePresenter.get_route_key(favorited)])
        )

      assert result == %{favorites: [favorited], others: [not_favorited]}
    end

    test "preserves relative order within each group" do
      fav_a = opportunity(%{technique: :exchange_spread, volume: 1})

      fav_b =
        opportunity(%{
          technique: :exchange_spread,
          volume: 2,
          via: [currency_amount("x", "X", 1)]
        })

      keys =
        MapSet.new([
          FlipOpportunityTablePresenter.get_route_key(fav_a),
          FlipOpportunityTablePresenter.get_route_key(fav_b)
        ])

      result = FlipOpportunityTablePresenter.partition_favorites([fav_a, fav_b], keys)

      assert result.favorites == [fav_a, fav_b]
    end
  end

  describe "build_display_groups/2" do
    test "filters by technique and threshold, sorts, then partitions favorites -- a filtered-out favorite disappears entirely" do
      kept_favorite = opportunity(%{technique: :exchange_spread, margin_percent: 90, volume: 1})

      filtered_out_favorite =
        opportunity(%{
          technique: :bulk_buy,
          margin_percent: 5,
          volume: 1,
          via: [currency_amount("y", "Y", 1)]
        })

      non_favorite =
        opportunity(%{
          technique: :exchange_spread,
          margin_percent: 50,
          volume: 2,
          via: [currency_amount("z", "Z", 1)]
        })

      result =
        FlipOpportunityTablePresenter.build_display_groups(
          [kept_favorite, filtered_out_favorite, non_favorite],
          %{
            enabled_techniques: %{@all_enabled | bulk_buy: false},
            enabled_categories: @all_categories_enabled,
            thresholds: %{},
            max_start_chaos: nil,
            sort_column: :margin,
            sort_direction: :desc,
            favorite_route_keys:
              MapSet.new([
                FlipOpportunityTablePresenter.get_route_key(kept_favorite),
                FlipOpportunityTablePresenter.get_route_key(filtered_out_favorite)
              ])
          }
        )

      assert result.favorites == [kept_favorite]
      assert result.others == [non_favorite]
    end
  end
end
