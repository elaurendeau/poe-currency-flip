defmodule PoeFlipFinder.DivinationCardReward do
  @moduledoc """
  A divination card's turn-in reward, manually captured and classified per
  docs/DATA_SOURCES.md. predictable = false for gamble/random-reward cards
  excluded from Feature C (see docs/PRD.md § 7.3) -- kept, not omitted, so
  the exclusion decision stays visible.

  Field is named `predictable`, not `predictable?` -- the `?` suffix is
  reserved for functions per docs/ELIXIR_CODE_STYLE.md; a struct field
  isn't a function call, and this struct will back an Ecto schema in
  Phase 3 where the field name maps directly to a DB column (which can't
  contain `?`).
  """

  alias PoeFlipFinder.Currency

  @enforce_keys [:card, :stack_size, :reward_currency, :reward_quantity, :predictable]
  defstruct [:card, :stack_size, :reward_currency, :reward_quantity, :predictable]

  @type t :: %__MODULE__{
          card: Currency.t(),
          stack_size: pos_integer(),
          reward_currency: Currency.t(),
          reward_quantity: pos_integer(),
          predictable: boolean()
        }
end
