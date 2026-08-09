defmodule PoeFlipFinder.League do
  @moduledoc """
  A league cached from GGG's public Leagues API. See docs/ARCHITECTURE.md
  § League Resolution for how has_exchange_activity is determined.
  """

  @enforce_keys [:external_id, :display_name, :is_current, :has_exchange_activity]
  defstruct [:id, :external_id, :display_name, :is_current, :has_exchange_activity, :start_at]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          external_id: String.t(),
          display_name: String.t(),
          is_current: boolean(),
          has_exchange_activity: boolean(),
          # From GGG's own `startAt` (docs/DATA_SOURCES.md § League List).
          # nil for a league only ever seen via raw trade data
          # (EctoLeagueReferenceGateway.resolve_or_create_league/1) and
          # never confirmed by a real Leagues API sync -- callers needing
          # league age (docs/PRD.md § 7.14) must treat nil as "unknown,"
          # never guess a start time.
          start_at: DateTime.t() | nil
        }
end
