defmodule PoeFlipFinder.Gateways.GggLeagueGateway do
  @moduledoc """
  The imperative-shell implementation of `PoeFlipFinder.LeagueGateway`,
  calling GGG's public Leagues API (docs/DATA_SOURCES.md § League List).
  This is the Anti-Corruption Layer boundary: everything above this module
  only ever sees `PoeFlipFinder.League`, never GGG's raw JSON shape.
  """

  @behaviour PoeFlipFinder.LeagueGateway

  alias PoeFlipFinder.League

  @default_base_url "https://api.pathofexile.com"

  @impl true
  def fetch_leagues do
    url = base_url() <> "/leagues"

    case Req.get(url, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, normalize(decode(body))}
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:poe_flip_finder, __MODULE__, [])[:base_url] || @default_base_url
  end

  defp decode(body) when is_binary(body), do: Jason.decode!(body)
  defp decode(body) when is_list(body), do: body

  @doc "Exposed so contract tests can exercise parsing without a live HTTP call."
  @spec normalize([map()]) :: [League.t()]
  def normalize(raw_leagues) do
    raw_leagues
    |> Enum.reject(&solo_self_found?/1)
    |> Enum.map(&to_entity/1)
  end

  defp solo_self_found?(raw), do: has_rule?(raw, "NoParties")

  defp to_entity(raw) do
    %League{
      id: nil,
      external_id: raw["id"],
      display_name: raw["name"],
      is_current: mainline_current_challenge_league?(raw),
      # Not yet cross-checked against ingested market data
      # (docs/ARCHITECTURE.md § League Resolution step 3) -- wired in once
      # the ingestion service exists (Phase 3/4 of the migration).
      has_exchange_activity: false
    }
  end

  # GGG flags every ruleset variant of the active challenge (softcore,
  # Hardcore, Ruthless, ...) with the same category.current=true, so that
  # flag alone matches more than one league -- only the plain variant with
  # no modifying rules is "the" mainline default from docs/PRD.md § 7.4.
  defp mainline_current_challenge_league?(raw) do
    is_current_category = get_in(raw, ["category", "current"]) == true
    is_current_category and not has_rule?(raw, "Hardcore") and not has_rule?(raw, "HardMode")
  end

  defp has_rule?(raw, rule_id) do
    Enum.any?(raw["rules"] || [], &(&1["id"] == rule_id))
  end
end
