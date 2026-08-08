defmodule PoeFlipFinder.Gateways.Schema.ExchangeMarketSnapshot do
  @moduledoc """
  Ecto mapping for the `exchange_market_snapshot` table (docs/SCHEMA.md §
  Ingestion state and market data). Plain FK id fields rather than
  `belongs_to` associations -- ids are already resolved by persistence
  time, and this avoids preload/N+1 concerns on what's meant to be a fast
  bulk-insert path (mirrors the Java version's same reasoning for using
  plain `long` FK columns over `@ManyToOne`).
  """

  use Ecto.Schema

  schema "exchange_market_snapshot" do
    field :generation_id, :integer
    field :league_id, :id
    field :currency_a_id, :id
    field :currency_b_id, :id
    field :snapshot_hour, :utc_datetime_usec
    field :volume_traded_a, :integer
    field :volume_traded_b, :integer
    field :lowest_stock_a, :integer
    field :highest_stock_a, :integer
    field :lowest_stock_b, :integer
    field :highest_stock_b, :integer
    field :lowest_ratio_a, :float
    field :highest_ratio_a, :float
    field :lowest_ratio_b, :float
    field :highest_ratio_b, :float
  end
end
