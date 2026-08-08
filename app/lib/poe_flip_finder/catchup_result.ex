defmodule PoeFlipFinder.CatchupResult do
  @moduledoc "The outcome of one bounded catch-up walk (see `PoeFlipFinder.Ingestion.run_ingestion_catchup/1`)."

  @enforce_keys [
    :hours_processed,
    :fully_caught_up,
    :last_processed_change_id,
    :skipped_unresolvable_market_entry_count
  ]
  defstruct [
    :hours_processed,
    :fully_caught_up,
    :last_processed_change_id,
    :skipped_unresolvable_market_entry_count
  ]

  @type t :: %__MODULE__{
          hours_processed: non_neg_integer(),
          fully_caught_up: boolean(),
          last_processed_change_id: integer(),
          skipped_unresolvable_market_entry_count: non_neg_integer()
        }
end
