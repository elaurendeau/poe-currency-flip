defmodule PoeFlipFinder.Gateways.Schema.Currency do
  @moduledoc "Ecto mapping for the `currency` table (docs/SCHEMA.md § Reference data)."

  use Ecto.Schema

  schema "currency" do
    field :external_id, :string
    field :display_name, :string
    field :icon_url, :string
    field :item_type, Ecto.Enum, values: [:currency, :divination_card]
  end
end
