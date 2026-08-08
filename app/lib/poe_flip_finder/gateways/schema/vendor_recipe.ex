defmodule PoeFlipFinder.Gateways.Schema.VendorRecipe do
  @moduledoc "Ecto mapping for the `vendor_recipe` table (docs/SCHEMA.md § Reference data)."

  use Ecto.Schema

  schema "vendor_recipe" do
    field :input_currency_id, :id
    field :input_quantity, :integer
    field :output_currency_id, :id
    field :output_quantity, :integer
  end
end
