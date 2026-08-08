defmodule PoeFlipFinder.ExchangeMarketSnapshot do
  @moduledoc """
  Normalized hourly market data for one currency pair, per docs/SCHEMA.md.
  Current-state only -- no history is retained; see the hot-swap generation
  model in docs/ARCHITECTURE.md § Currency Exchange Ingestion.
  """

  alias PoeFlipFinder.{Currency, League}

  @enforce_keys [
    :generation_id,
    :league,
    :currency_a,
    :currency_b,
    :snapshot_hour,
    :volume_traded_a,
    :volume_traded_b,
    :lowest_stock_a,
    :highest_stock_a,
    :lowest_stock_b,
    :highest_stock_b,
    :lowest_ratio_a,
    :highest_ratio_a,
    :lowest_ratio_b,
    :highest_ratio_b
  ]
  defstruct [
    :id,
    :generation_id,
    :league,
    :currency_a,
    :currency_b,
    :snapshot_hour,
    :volume_traded_a,
    :volume_traded_b,
    :lowest_stock_a,
    :highest_stock_a,
    :lowest_stock_b,
    :highest_stock_b,
    :lowest_ratio_a,
    :highest_ratio_a,
    :lowest_ratio_b,
    :highest_ratio_b
  ]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          generation_id: integer(),
          league: League.t(),
          currency_a: Currency.t(),
          currency_b: Currency.t(),
          snapshot_hour: DateTime.t(),
          volume_traded_a: integer(),
          volume_traded_b: integer(),
          lowest_stock_a: integer(),
          highest_stock_a: integer(),
          lowest_stock_b: integer(),
          highest_stock_b: integer(),
          lowest_ratio_a: float(),
          highest_ratio_a: float(),
          lowest_ratio_b: float(),
          highest_ratio_b: float()
        }
end
