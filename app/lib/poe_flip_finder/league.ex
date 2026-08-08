defmodule PoeFlipFinder.League do
  @moduledoc """
  A league cached from GGG's public Leagues API. See docs/ARCHITECTURE.md
  § League Resolution for how has_exchange_activity is determined.
  """

  @enforce_keys [:external_id, :display_name, :is_current, :has_exchange_activity]
  defstruct [:id, :external_id, :display_name, :is_current, :has_exchange_activity]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          external_id: String.t(),
          display_name: String.t(),
          is_current: boolean(),
          has_exchange_activity: boolean()
        }
end
