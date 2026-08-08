defmodule PoeFlipFinder.CatchupCapPolicy do
  @moduledoc """
  The two tuning knobs for one bounded catch-up walk
  (docs/ARCHITECTURE.md § Currency Exchange Ingestion), bundled since
  they're always supplied together from application config.
  """

  @enforce_keys [:max_hours_per_call, :first_run_lookback_hours]
  defstruct [:max_hours_per_call, :first_run_lookback_hours]

  @type t :: %__MODULE__{
          max_hours_per_call: pos_integer(),
          first_run_lookback_hours: pos_integer()
        }
end
