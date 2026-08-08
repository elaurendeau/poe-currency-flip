defmodule PoeFlipFinder.LeagueReferenceGateway do
  @moduledoc """
  Defined by the core: resolve a league string from the Currency Exchange
  payload to a persisted League row, creating one on first sight. Unlike
  currency resolution this can't fail -- the league name arrives directly
  in the payload, no external lookup needed. Marks has_exchange_activity,
  the real gate for League Resolution step 3 (docs/SCHEMA.md § League
  cache, docs/ARCHITECTURE.md § League Resolution).
  """

  alias PoeFlipFinder.League

  @callback resolve_or_create_league(league_external_id :: String.t()) :: League.t()
end
