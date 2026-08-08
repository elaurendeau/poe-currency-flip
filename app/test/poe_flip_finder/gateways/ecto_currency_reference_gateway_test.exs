defmodule PoeFlipFinder.Gateways.EctoCurrencyReferenceGatewayTest do
  use PoeFlipFinder.DataCase, async: true

  alias PoeFlipFinder.Currency
  alias PoeFlipFinder.Gateways.EctoCurrencyReferenceGateway
  alias PoeFlipFinder.StubItemIconGateway

  setup do
    Application.put_env(:poe_flip_finder, :item_icon_gateway, StubItemIconGateway)
    on_exit(fn -> Application.delete_env(:poe_flip_finder, :item_icon_gateway) end)
    :ok
  end

  test "resolves an already-persisted currency without consulting the item icon gateway" do
    {:ok, existing} =
      %PoeFlipFinder.Gateways.Schema.Currency{}
      |> Ecto.Changeset.change(
        external_id: "Metadata/Items/Currency/CurrencyPortal",
        display_name: "Portal Scroll",
        category: :currency
      )
      |> Repo.insert()

    # No stub configured -- if this fell through to the item icon gateway,
    # lookup_item/1 would return nil (Process.get default) and the
    # currency would never be found, so a passing assertion here proves
    # the DB-first path is what actually ran.
    result =
      EctoCurrencyReferenceGateway.resolve_or_create_currency(
        "Metadata/Items/Currency/CurrencyPortal"
      )

    assert result.id == existing.id
    assert result.display_name == "Portal Scroll"
  end

  test "creates a currency on first sight via the item icon gateway" do
    StubItemIconGateway.stub("Metadata/Items/Currency/CurrencyPortal", %Currency{
      id: nil,
      external_id: "Metadata/Items/Currency/CurrencyPortal",
      display_name: "Portal Scroll",
      icon_url: "https://www.pathofexile.com/gen/image/x.png",
      category: :currency
    })

    result =
      EctoCurrencyReferenceGateway.resolve_or_create_currency(
        "Metadata/Items/Currency/CurrencyPortal"
      )

    assert result.id != nil
    assert result.display_name == "Portal Scroll"

    assert Repo.get_by(PoeFlipFinder.Gateways.Schema.Currency,
             external_id: "Metadata/Items/Currency/CurrencyPortal"
           )
  end

  test "returns nil when the item genuinely can't be resolved, without creating a row" do
    # StubItemIconGateway.lookup_item/1 returns nil by default (no stub configured).
    result =
      EctoCurrencyReferenceGateway.resolve_or_create_currency(
        "Metadata/Items/Currency/CurrencyUnknown"
      )

    assert result == nil

    refute Repo.get_by(PoeFlipFinder.Gateways.Schema.Currency,
             external_id: "Metadata/Items/Currency/CurrencyUnknown"
           )
  end
end
