defmodule PoeFlipFinder.Gateways.Schema.Currency do
  @moduledoc "Ecto mapping for the `currency` table (docs/SCHEMA.md § Reference data)."

  use Ecto.Schema

  schema "currency" do
    field :external_id, :string
    field :display_name, :string
    field :icon_url, :string

    field :category, Ecto.Enum,
      values: [
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
  end
end
