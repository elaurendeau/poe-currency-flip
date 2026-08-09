defmodule PoeFlipFinder.HistoricalPricePattern do
  @moduledoc """
  One item's real, day-indexed chaos price series across a small sample of
  past leagues, manually captured from poe-antiquary.xyz per
  docs/DATA_SOURCES.md § Historical League Price Archive. Backs
  docs/PRD.md § 7.14 Feature N -- Historical Investment.

  Every point is a real observed value -- no interpolation, no synthetic
  hour-level precision the source data doesn't actually have. A league's
  `day_prices` is whatever real days poe-antiquary has for that item in
  that league; it does not always start at day 0 (some items only start
  trading once players reach a certain point in progression -- e.g. a
  beast-crafted unique with no day-0 buyers yet) and different leagues can
  cover different day ranges for the same item.

  `currency` carries a name-only placeholder `Currency` (no `id`/
  `external_id`), the same treatment `VendorRecipe`/`DivinationCardReward`
  entries get from their own bundled reference gateways -- this source has
  no access to live Currency Exchange data to resolve those against.
  `currency.category` reuses this app's real `Currency.category` enum
  wherever the category is genuinely GGG-tradeable (so a later live-price
  cross-check, docs/PRD.md § 7.14, can filter `exchange_market_snapshot`
  by it); two categories poe-antiquary has real data for but that never
  trade on the Currency Exchange (Cluster Jewels; special/transfigured
  gems) use additional atoms not in the DB check-constraint enum -- safe
  here because this placeholder Currency is never persisted via Ecto.
  """

  alias PoeFlipFinder.Currency

  defmodule DayPrice do
    @moduledoc "One real observed chaos price at a specific league-day index."

    @enforce_keys [:day, :chaos]
    defstruct [:day, :chaos]

    @type t :: %__MODULE__{day: non_neg_integer(), chaos: float()}
  end

  defmodule LeagueObservation do
    @moduledoc """
    One past league's real day-indexed price series for the parent
    HistoricalPricePattern's item. `day_prices` is ordered ascending by
    `day` and is whatever real days the source has -- not guaranteed to
    start at day 0 or be contiguous.
    """

    @enforce_keys [:league, :day_prices]
    defstruct [:league, :day_prices]

    @type t :: %__MODULE__{league: String.t(), day_prices: [DayPrice.t()]}
  end

  @enforce_keys [:currency, :league_observations]
  defstruct [:currency, :league_observations]

  @type t :: %__MODULE__{
          currency: Currency.t(),
          league_observations: [LeagueObservation.t()]
        }
end
