defmodule PoeFlipFinder.ExchangeMarketEntry do
  @moduledoc """
  One normalized-but-not-yet-resolved market entry from the Currency
  Exchange change-stream -- external ids as raw strings, since resolving
  them into Currency/League entities is a reference-data lookup's job, not
  this seam's.
  """

  @enforce_keys [
    :league_external_id,
    :currency_a_external_id,
    :currency_b_external_id,
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
    :league_external_id,
    :currency_a_external_id,
    :currency_b_external_id,
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
          league_external_id: String.t(),
          currency_a_external_id: String.t(),
          currency_b_external_id: String.t(),
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
