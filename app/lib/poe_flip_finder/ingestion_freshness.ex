defmodule PoeFlipFinder.IngestionFreshness do
  @moduledoc """
  The ingestion checkpoint/staleness state. Both fields `nil` means
  ingestion has never completed a successful run. Serves both the
  checkpoint read during a catch-up walk and the freshness-read use case
  -- one read model, two callers.
  """

  @enforce_keys [:last_processed_change_id, :active_generation_refreshed_at]
  defstruct [:last_processed_change_id, :active_generation_refreshed_at]

  @type t :: %__MODULE__{
          last_processed_change_id: integer() | nil,
          active_generation_refreshed_at: DateTime.t() | nil
        }
end
