defmodule PoeFlipFinder.DivinationCardReward do
  @moduledoc """
  A divination card's turn-in reward, manually captured and classified per
  docs/DATA_SOURCES.md. is_predictable? = false for gamble/random-reward
  cards excluded from Feature C (see docs/PRD.md § 7.3) -- kept, not
  omitted, so the exclusion decision stays visible.
  """

  alias PoeFlipFinder.Currency

  @enforce_keys [:card, :stack_size, :reward_currency, :reward_quantity, :predictable?]
  defstruct [:card, :stack_size, :reward_currency, :reward_quantity, :predictable?]

  @type t :: %__MODULE__{
          card: Currency.t(),
          stack_size: pos_integer(),
          reward_currency: Currency.t(),
          reward_quantity: pos_integer(),
          predictable?: boolean()
        }
end
