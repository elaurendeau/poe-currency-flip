defmodule PoeFlipFinder.Gateways.Schema.ExchangeIngestionState do
  @moduledoc """
  Ecto mapping for the singleton `exchange_ingestion_state` row
  (docs/SCHEMA.md § Ingestion state and market data). The migration seeds
  row id=1 with active_generation_id=0 as the "no generation yet" sentinel
  -- this app never inserts a new row, only updates the existing one.
  """

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: false}
  schema "exchange_ingestion_state" do
    field :last_processed_change_id, :integer
    field :active_generation_id, :integer, default: 0
    field :active_generation_refreshed_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end
