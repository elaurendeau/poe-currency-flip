defmodule PoeFlipFinder.Gateways.GggExchangeSourceGatewayTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.GggExchangeSourceGateway

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: a saved real API
  # response in, an asserted normalized domain object out -- served through
  # Bypass (a real local HTTP server) rather than a mock, so the actual
  # HTTP client path is exercised too, not just the JSON-parsing logic the
  # Java version's package-visible normalize() test covered.

  @requested_change_id 1_785_985_200

  setup do
    bypass = Bypass.open()

    Application.put_env(:poe_flip_finder, GggExchangeSourceGateway,
      base_url: "http://localhost:#{bypass.port}"
    )

    on_exit(fn -> Application.delete_env(:poe_flip_finder, GggExchangeSourceGateway) end)
    {:ok, bypass: bypass}
  end

  test "parses all market entries regardless of item category", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api/currency-exchange/#{@requested_change_id}", fn conn ->
      Plug.Conn.resp(conn, 200, fixture("single_hour_page.json"))
    end)

    {:ok, page} = GggExchangeSourceGateway.fetch_hour(@requested_change_id)

    assert page.at_tip == false
    assert page.next_change_id == 1_785_988_800

    external_ids = Enum.map(page.entries, & &1.currency_a_external_id)

    assert length(page.entries) == 4

    assert Enum.sort(external_ids) ==
             Enum.sort([
               "Metadata/Items/Currency/CurrencyBreachUpgradeUniqueGeneral",
               "Metadata/Items/Currency/CurrencyJewelleryQualityVaal",
               "Metadata/Items/DivinationCards/DivinationCardTheApothecary",
               "Metadata/Items/AtlasExiles/AddModToRareCrusader"
             ])
  end

  test "pulls per-side values from the correct item path key", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/api/currency-exchange/#{@requested_change_id}", fn conn ->
      Plug.Conn.resp(conn, 200, fixture("single_hour_page.json"))
    end)

    {:ok, page} = GggExchangeSourceGateway.fetch_hour(@requested_change_id)

    card_entry =
      Enum.find(page.entries, &String.contains?(&1.currency_a_external_id, "DivinationCard"))

    assert card_entry.league_external_id == "Standard"
    assert card_entry.currency_b_external_id == "Metadata/Items/Currency/CurrencyModValues"
    assert card_entry.volume_traded_a == 2
    assert card_entry.volume_traded_b == 80
    assert card_entry.lowest_stock_a == 203
    assert card_entry.highest_stock_a == 210
    assert card_entry.lowest_ratio_a == 1.0
    assert card_entry.highest_ratio_b == 40.0
    assert card_entry.snapshot_hour == DateTime.from_unix!(@requested_change_id)
  end

  test "at tip returns no entries but still reports next_change_id", %{bypass: bypass} do
    tip_change_id = 1_785_988_800

    Bypass.expect_once(bypass, "GET", "/api/currency-exchange/#{tip_change_id}", fn conn ->
      Plug.Conn.resp(conn, 404, fixture("tip_404.json"))
    end)

    {:ok, page} = GggExchangeSourceGateway.fetch_hour(tip_change_id)

    assert page.at_tip == true
    assert page.entries == []
    assert page.next_change_id == 1_785_988_800
  end

  test "an unexpected HTTP status is a reported error, not a crash or a silent empty page", %{
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "GET", "/api/currency-exchange/#{@requested_change_id}", fn conn ->
      Plug.Conn.resp(conn, 500, "internal error")
    end)

    assert {:error, {:unexpected_status, 500}} =
             GggExchangeSourceGateway.fetch_hour(@requested_change_id)
  end

  test "the server being unreachable is a reported error, not a crash", %{bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, _reason} = GggExchangeSourceGateway.fetch_hour(@requested_change_id)
  end

  defp fixture(filename) do
    Path.join([__DIR__, "..", "..", "fixtures", "ggg_exchange", filename]) |> File.read!()
  end
end
