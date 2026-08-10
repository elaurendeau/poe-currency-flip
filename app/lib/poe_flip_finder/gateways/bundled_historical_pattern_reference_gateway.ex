defmodule PoeFlipFinder.Gateways.BundledHistoricalPatternReferenceGateway do
  @moduledoc """
  The imperative-shell implementation of
  `PoeFlipFinder.HistoricalPatternReferenceGateway`, reading a small,
  manually-captured sample of past-league price data (docs/DATA_SOURCES.md
  § Historical League Price Archive) from a bundled resource -- same
  treatment as `BundledVendorRecipeReferenceGateway`, since poe-antiquary
  has no live API contract worth depending on and the underlying data
  (past, concluded leagues) doesn't change.

  The parsed list is cached in `:persistent_term` after first load, same
  rationale as the other bundled reference gateways: small,
  effectively-immutable data read on every Historical Investment render.
  """

  @behaviour PoeFlipFinder.HistoricalPatternReferenceGateway

  alias PoeFlipFinder.{Currency, HistoricalPricePattern}
  alias PoeFlipFinder.Gateways.IconByDisplayNameResolver
  alias PoeFlipFinder.HistoricalPricePattern.{DayPrice, LeagueObservation}

  @catalog_resource_path "reference-data/historical-investment-patterns.json"
  @persistent_term_key {__MODULE__, :historical_patterns}

  @impl true
  def find_all, do: ensure_loaded()

  defp ensure_loaded do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        patterns = normalize(Jason.decode!(read_bundled_catalog()))
        :persistent_term.put(@persistent_term_key, patterns)
        patterns

      patterns ->
        patterns
    end
  end

  defp read_bundled_catalog do
    :poe_flip_finder
    |> Application.app_dir("priv")
    |> Path.join(@catalog_resource_path)
    |> File.read!()
  end

  @doc "Exposed so contract tests can exercise parsing without reading the bundled file."
  @spec normalize([map()]) :: [HistoricalPricePattern.t()]
  def normalize(raw_entries), do: Enum.map(raw_entries, &to_entity/1)

  defp to_entity(entry) do
    %HistoricalPricePattern{
      currency: placeholder_currency(entry["currencyName"], entry["category"]),
      league_observations: Enum.map(entry["leagueObservations"], &to_observation/1)
    }
  end

  defp to_observation(entry) do
    %LeagueObservation{
      league: entry["league"],
      day_prices: Enum.map(entry["days"], &to_day_price/1)
    }
  end

  defp to_day_price(entry) do
    %DayPrice{day: entry["day"], chaos: entry["chaos"] * 1.0}
  end

  defp placeholder_currency(name, raw_category) do
    %Currency{
      id: nil,
      external_id: nil,
      display_name: name,
      icon_url: IconByDisplayNameResolver.resolve(name),
      category: to_category(raw_category)
    }
  end

  # Deliberately NOT String.to_existing_atom/1: whether ":cards" (etc.) is
  # already interned depends on which other modules happened to load
  # first in the current run -- confirmed to raise a real
  # ArgumentError ("not an already existing atom") when this gateway's
  # own test file runs in isolation, since nothing had referenced that
  # atom yet. An explicit map is immune to load order and, per
  # docs/CODE_STYLE.md's error-handling section, fails loudly with a
  # specific error on a genuinely unrecognized category rather than
  # crashing on an unrelated-looking ArgumentError.
  @known_categories %{
    "currency" => :currency,
    "cards" => :cards,
    "essences" => :essences,
    "beasts" => :beasts,
    "ancestor" => :ancestor,
    "oils" => :oils,
    "cluster_jewels" => :cluster_jewels
  }

  defp to_category(raw_category) do
    Map.get(@known_categories, raw_category) ||
      raise ArgumentError, "unrecognized Historical Investment category: #{inspect(raw_category)}"
  end
end
