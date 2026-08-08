defmodule PoeFlipFinder.DivinationCardReferenceGateway do
  @moduledoc """
  Defined by the core for whatever it needs from divination card turn-in
  reward data (docs/DATA_SOURCES.md § Divination Card Turn-In Rewards).

  Returned rewards carry name-only placeholder `Currency` structs for the
  card and reward currency (no `id`/`external_id`) -- this gateway has no
  access to live Currency Exchange data to resolve those. Callers must
  match by `Currency.display_name` against currently-active market
  snapshots to get a fully-resolved Currency before using one in a
  FlipOpportunity, the same treatment `ItemIconGateway` results get.
  """

  alias PoeFlipFinder.DivinationCardReward

  @callback find_all() :: [DivinationCardReward.t()]
end
