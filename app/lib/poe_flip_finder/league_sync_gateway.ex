defmodule PoeFlipFinder.LeagueSyncGateway do
  @moduledoc """
  Write side of the league cache, populated from a live GGG Leagues API
  fetch (docs/PRD.md § 7.7 manual refresh). Deliberately separate from
  `PoeFlipFinder.LeagueReferenceGateway`, which resolves/creates a league
  from the Currency Exchange ingestion payload instead -- different
  caller, different data available at that seam (only an id string, no
  display name or current-league flag). This gateway updates
  display_name/is_current from the richer GGG payload while preserving
  whatever has_exchange_activity ingestion already determined.
  """

  alias PoeFlipFinder.League

  @callback upsert_from_ggg(leagues :: [League.t()]) :: [League.t()]
end
