defmodule PoeFlipFinder.FlipOpportunity do
  @moduledoc """
  A computed flip result, matching the Start/Via/Sell/Margin/Profit/Volume
  row structure in docs/TECH_STACK.md § UI Style. Never persisted -- see
  docs/SCHEMA.md § Deliberately not a table: computed fresh on every refresh.
  """

  alias PoeFlipFinder.CurrencyAmount

  @type technique :: :vendor_recipe | :exchange_spread | :divination_card | :bulk_buy

  @enforce_keys [:technique, :start, :via, :sell, :margin_percent, :profit, :volume, :detail]
  defstruct [:technique, :start, :via, :sell, :margin_percent, :profit, :volume, :detail]

  @type t :: %__MODULE__{
          technique: technique(),
          start: [CurrencyAmount.t()],
          via: [CurrencyAmount.t()],
          sell: [CurrencyAmount.t()],
          margin_percent: float(),
          # Always denominated in Chaos Orb, per TECH_STACK.md's row design --
          # never the start currency's own unit.
          profit: CurrencyAmount.t(),
          volume: float(),
          detail: String.t()
        }
end
