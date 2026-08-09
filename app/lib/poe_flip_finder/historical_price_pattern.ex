defmodule PoeFlipFinder.HistoricalPricePattern do
  @moduledoc """
  One item's day-0/day-1/day-2 chaos price across a small sample of past
  leagues, manually captured from poe-antiquary.xyz per
  docs/DATA_SOURCES.md § Historical League Price Archive. Backs
  docs/PRD.md § 7.14 Feature N -- Historical Investment.

  `currency` carries a name-only placeholder `Currency` (no `id`/
  `external_id`), the same treatment `VendorRecipe`/`DivinationCardReward`
  entries get from their own bundled reference gateways -- this source has
  no access to live Currency Exchange data to resolve those against.
  """

  alias PoeFlipFinder.Currency

  defmodule LeagueObservation do
    @moduledoc """
    One past league's day-0/day-1/day-2 chaos price for the parent
    HistoricalPricePattern's item.
    """

    @enforce_keys [:league, :day0_chaos, :day1_chaos, :day2_chaos]
    defstruct [:league, :day0_chaos, :day1_chaos, :day2_chaos]

    @type t :: %__MODULE__{
            league: String.t(),
            day0_chaos: float(),
            day1_chaos: float(),
            day2_chaos: float()
          }
  end

  @enforce_keys [:currency, :league_observations]
  defstruct [:currency, :league_observations]

  @type t :: %__MODULE__{
          currency: Currency.t(),
          league_observations: [LeagueObservation.t()]
        }
end
