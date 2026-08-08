defmodule PoeFlipFinder.Gateways.Schema.DivinationCard do
  @moduledoc "Ecto mapping for the `divination_card` table (docs/SCHEMA.md § Reference data)."

  use Ecto.Schema

  @primary_key {:currency_id, :id, autogenerate: false}
  schema "divination_card" do
    field :stack_size, :integer
    field :reward_currency_id, :id
    field :reward_quantity, :integer
    field :predictable, :boolean, default: false
  end
end
