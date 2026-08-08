defmodule PoeFlipFinder.LeagueGateway do
  @moduledoc """
  Defined by the core for whatever it needs from GGG's public Leagues API.
  Callers use this without knowing whether the implementation is the real
  GGG API or a test double.
  """

  alias PoeFlipFinder.League

  @doc """
  Fetches the current league list, already filtered to exclude Solo
  Self-Found leagues (no Currency Exchange access) per
  docs/ARCHITECTURE.md § League Resolution steps 1-2.
  """
  @callback fetch_leagues() :: {:ok, [League.t()]} | {:error, term()}
end
