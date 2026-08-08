defmodule PoeFlipFinder.DivineChaosRateTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.{Currency, DivineChaosRate, ExchangeMarketSnapshot, League}

  @league %League{
    id: 1,
    external_id: "Standard",
    display_name: "Standard",
    is_current: false,
    has_exchange_activity: true
  }
  @chaos %Currency{
    id: 1,
    external_id: "Metadata/Items/Currency/CurrencyRerollRare",
    display_name: "Chaos Orb",
    category: :currency
  }
  @divine %Currency{
    id: 2,
    external_id: "Metadata/Items/Currency/CurrencyModValues",
    display_name: "Divine Orb",
    category: :currency
  }
  @wisdom %Currency{
    id: 3,
    external_id: "Metadata/Items/Currency/CurrencyIdentification",
    display_name: "Scroll of Wisdom",
    category: :currency
  }

  defp snapshot(
         currency_a,
         currency_b,
         lowest_ratio_a,
         lowest_ratio_b,
         highest_ratio_a,
         highest_ratio_b
       ) do
    %ExchangeMarketSnapshot{
      id: 1,
      generation_id: 1,
      league: @league,
      currency_a: currency_a,
      currency_b: currency_b,
      snapshot_hour: DateTime.utc_now(),
      volume_traded_a: 100,
      volume_traded_b: 100,
      lowest_stock_a: 50,
      highest_stock_a: 60,
      lowest_stock_b: 50,
      highest_stock_b: 60,
      lowest_ratio_a: lowest_ratio_a,
      highest_ratio_a: highest_ratio_a,
      lowest_ratio_b: lowest_ratio_b,
      highest_ratio_b: highest_ratio_b
    }
  end

  test "resolves the rate as chaos received per 1 divine, averaged from both extremes, chaos in slot A" do
    snapshots = [snapshot(@chaos, @divine, 200, 1, 220, 1)]

    rate = DivineChaosRate.resolve(snapshots)

    assert rate.chaos_currency == @chaos
    assert rate.divine_currency == @divine
    assert rate.chaos_per_divine == 210.0
  end

  test "resolves correctly when chaos is in slot B instead of A" do
    snapshots = [snapshot(@divine, @chaos, 1, 200, 1, 220)]

    rate = DivineChaosRate.resolve(snapshots)

    assert rate.chaos_currency == @chaos
    assert rate.divine_currency == @divine
    assert rate.chaos_per_divine == 210.0
  end

  test "returns nil when no chaos/divine pair is present" do
    snapshots = [snapshot(@chaos, @wisdom, 1, 185, 1, 366)]

    assert DivineChaosRate.resolve(snapshots) == nil
  end

  test "returns nil for an empty snapshot list" do
    assert DivineChaosRate.resolve([]) == nil
  end
end
