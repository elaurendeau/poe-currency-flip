defmodule PoeFlipFinder.Leagues do
  @moduledoc """
  League list read and refresh (docs/ARCHITECTURE.md § League Resolution).
  """

  alias PoeFlipFinder.League

  @doc """
  A DB-cached read, not a live GGG call -- every page load hitting GGG
  directly made the league dropdown feel perpetually loading. The live
  fetch + cache population happens in `refresh_league_list/0` instead,
  triggered only by the user's explicit "Refresh leagues" action
  (docs/PRD.md § 7.7).
  """
  @spec resolve_league_list() :: [League.t()]
  def resolve_league_list, do: league_query_gateway().find_all_leagues()

  @doc """
  The only place that ever calls out to GGG's live Leagues API. Syncs the
  fetched leagues into the cache so subsequent reads
  (`resolve_league_list/0`) stay fast and don't depend on GGG being
  reachable. A fetch failure propagates as `{:error, reason}` rather than
  being swallowed -- fail loudly at the boundary, per
  docs/ARCHITECTURE.md § Failure Handling.
  """
  @spec refresh_league_list() :: {:ok, [League.t()]} | {:error, term()}
  def refresh_league_list do
    with {:ok, fetched} <- league_gateway().fetch_leagues() do
      {:ok, league_sync_gateway().upsert_from_ggg(fetched)}
    end
  end

  defp league_query_gateway do
    Application.get_env(
      :poe_flip_finder,
      :league_query_gateway,
      PoeFlipFinder.Gateways.EctoLeagueQueryGateway
    )
  end

  defp league_gateway do
    Application.get_env(
      :poe_flip_finder,
      :league_gateway,
      PoeFlipFinder.Gateways.GggLeagueGateway
    )
  end

  defp league_sync_gateway do
    Application.get_env(
      :poe_flip_finder,
      :league_sync_gateway,
      PoeFlipFinder.Gateways.EctoLeagueSyncGateway
    )
  end
end
