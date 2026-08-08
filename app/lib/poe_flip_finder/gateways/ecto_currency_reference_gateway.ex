defmodule PoeFlipFinder.Gateways.EctoCurrencyReferenceGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.CurrencyReferenceGateway`.
  Depends on the `PoeFlipFinder.ItemIconGateway` behaviour (configurable via
  `:item_icon_gateway` app env, defaulting to the real GGG adapter), not
  the concrete Ggg module directly -- Dependency Inversion, and lets a test
  double stand in during testing.
  """

  @behaviour PoeFlipFinder.CurrencyReferenceGateway

  alias PoeFlipFinder.Currency
  alias PoeFlipFinder.Gateways.Schema
  alias PoeFlipFinder.Repo

  @impl true
  def resolve_or_create_currency(external_id) do
    case Repo.get_by(Schema.Currency, external_id: external_id) do
      nil -> create_from_item_icon_gateway(external_id)
      schema -> to_entity(schema)
    end
  end

  defp create_from_item_icon_gateway(external_id) do
    case item_icon_gateway().lookup_item(external_id) do
      nil ->
        nil

      %Currency{} = resolved ->
        %Schema.Currency{}
        |> Ecto.Changeset.change(
          external_id: resolved.external_id,
          display_name: resolved.display_name,
          icon_url: resolved.icon_url,
          item_type: resolved.item_type
        )
        |> Repo.insert!()
        |> to_entity()
    end
  end

  defp item_icon_gateway do
    Application.get_env(
      :poe_flip_finder,
      :item_icon_gateway,
      PoeFlipFinder.Gateways.GggItemIconGateway
    )
  end

  defp to_entity(%Schema.Currency{} = schema) do
    %Currency{
      id: schema.id,
      external_id: schema.external_id,
      display_name: schema.display_name,
      icon_url: schema.icon_url,
      item_type: schema.item_type
    }
  end
end
