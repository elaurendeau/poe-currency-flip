defmodule PoeFlipFinder.Gateways.Schema.League do
  @moduledoc "Ecto mapping for the `league` table (docs/SCHEMA.md § League cache)."

  use Ecto.Schema

  schema "league" do
    field :external_id, :string
    field :display_name, :string
    field :is_current, :boolean, default: false
    field :has_exchange_activity, :boolean, default: false
    field :known_to_ggg, :boolean, default: false
  end
end
