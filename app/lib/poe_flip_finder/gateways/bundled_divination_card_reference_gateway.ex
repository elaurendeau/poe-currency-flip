defmodule PoeFlipFinder.Gateways.BundledDivinationCardReferenceGateway do
  @moduledoc """
  The imperative-shell implementation of
  `PoeFlipFinder.DivinationCardReferenceGateway`, reading manually-captured
  PoE Wiki turn-in reward data (docs/DATA_SOURCES.md § Divination Card
  Turn-In Rewards) from a bundled resource -- same treatment as
  `GggItemIconGateway`'s Item Icons catalog, since neither source has a
  live API to fetch from.

  The `card`/`reward_currency` fields of returned `DivinationCardReward`
  entities are name-only placeholders (no `id`, `external_id`, or
  `icon_url`) -- this gateway has no access to live Currency Exchange data
  to resolve those against. Callers must match by `Currency.display_name`
  against currently-active market snapshots to get a fully-resolved
  Currency before using one in a FlipOpportunity.

  The parsed list is cached in `:persistent_term` after first load, same
  rationale as `GggItemIconGateway`: small, effectively-immutable data read
  on every flip-opportunities computation.
  """

  @behaviour PoeFlipFinder.DivinationCardReferenceGateway

  alias PoeFlipFinder.{Currency, DivinationCardReward}

  @catalog_resource_path "reference-data/divination-card-rewards.json"
  @persistent_term_key {__MODULE__, :card_rewards}

  @impl true
  def find_all, do: ensure_loaded()

  defp ensure_loaded do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        rewards = normalize(Jason.decode!(read_bundled_catalog()))
        :persistent_term.put(@persistent_term_key, rewards)
        rewards

      rewards ->
        rewards
    end
  end

  defp read_bundled_catalog do
    :poe_flip_finder
    |> Application.app_dir("priv")
    |> Path.join(@catalog_resource_path)
    |> File.read!()
  end

  @doc "Exposed so contract tests can exercise parsing without reading the bundled file."
  @spec normalize([map()]) :: [DivinationCardReward.t()]
  def normalize(raw_entries), do: Enum.map(raw_entries, &to_entity/1)

  defp to_entity(entry) do
    %DivinationCardReward{
      card: placeholder_currency(entry["cardName"], :cards),
      stack_size: entry["stackSize"],
      reward_currency: placeholder_reward_currency(entry["rewardCurrencyName"]),
      reward_quantity: entry["rewardQuantity"] || 0,
      predictable: entry["isPredictable"]
    }
  end

  defp placeholder_reward_currency(nil), do: nil
  defp placeholder_reward_currency(name), do: placeholder_currency(name, :currency)

  defp placeholder_currency(name, category) do
    %Currency{
      id: nil,
      external_id: nil,
      display_name: name,
      icon_url: nil,
      category: category
    }
  end
end
