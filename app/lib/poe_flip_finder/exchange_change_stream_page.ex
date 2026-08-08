defmodule PoeFlipFinder.ExchangeChangeStreamPage do
  @moduledoc "One page of the Currency Exchange change-stream, crossing the ExchangeSourceGateway seam."

  alias PoeFlipFinder.ExchangeMarketEntry

  @enforce_keys [:entries, :next_change_id, :at_tip]
  defstruct [:entries, :next_change_id, :at_tip]

  @type t :: %__MODULE__{
          entries: [ExchangeMarketEntry.t()],
          next_change_id: integer(),
          # Named `at_tip`, not `at_tip?` -- see docs/ELIXIR_CODE_STYLE.md;
          # the `?` suffix is reserved for functions, not struct fields.
          at_tip: boolean()
        }
end
