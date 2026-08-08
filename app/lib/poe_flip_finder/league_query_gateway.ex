defmodule PoeFlipFinder.LeagueQueryGateway do
  @moduledoc """
  Read side of the league cache (docs/SCHEMA.md § League cache) --
  deliberately separate from `PoeFlipFinder.LeagueGateway` (the live GGG
  fetch) and `PoeFlipFinder.LeagueSyncGateway` (the write side), since each
  has a different caller and lifecycle: this one backs the cheap
  `GET /leagues` read every page load makes, so it must never itself call
  out to GGG.
  """

  alias PoeFlipFinder.League

  @callback find_all_leagues() :: [League.t()]
end
