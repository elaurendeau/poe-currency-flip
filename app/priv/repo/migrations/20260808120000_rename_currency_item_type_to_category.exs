defmodule PoeFlipFinder.Repo.Migrations.RenameCurrencyItemTypeToCategory do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  alias PoeFlipFinder.Gateways.GggItemIconGateway

  # docs/SCHEMA.md: `currency.item_type` (2 values) widens to `category` (23
  # values), one per group in the bundled Item Icons catalog
  # (docs/DATA_SOURCES.md § Item Icons) -- see GggItemIconGateway for the
  # full group-id -> category mapping this migration reuses for the backfill
  # below.
  @category_values ~w(
    cards fragments ancestor essences currency beasts map_key heist
    runegrafts delve sanctum maps_unique delirium_orbs oils catalysts
    ducats maps_special allflame_embers keepers enshrouding_crystals
    legacy expedition misc
  )

  def up do
    drop constraint(:currency, :item_type_must_be_known)
    rename table(:currency), :item_type, to: :category

    create constraint(:currency, :category_must_be_known,
             check: "category IN (#{Enum.map_join(@category_values, ", ", &"'#{&1}'")})"
           )

    flush()
    backfill_categories()
  end

  def down do
    # currency is pure cache (docs/SCHEMA.md) -- coarsen back to the old
    # 2-value taxonomy before the column (and its check constraint) revert,
    # since almost every real category value here is invalid under the old
    # constraint.
    execute("UPDATE currency SET category = 'divination_card' WHERE category = 'cards'")
    execute("UPDATE currency SET category = 'currency' WHERE category != 'divination_card'")

    drop constraint(:currency, :category_must_be_known)
    rename table(:currency), :category, to: :item_type

    create constraint(:currency, :item_type_must_be_known,
             check: "item_type IN ('currency', 'divination_card')"
           )
  end

  # Every existing currency row is 100% re-derivable from its already-stored
  # external_id plus the bundled Item Icons catalog -- the same source
  # EctoCurrencyReferenceGateway.resolve_or_create_currency/1 uses to create
  # rows in the first place. Re-running that same lookup here repairs rows
  # that were only ever coarsely classified under the old 2-value
  # item_type. A row whose external_id no longer matches anything in the
  # catalog (stale/edge case) keeps a coarse fallback derived from its old
  # item_type instead of failing the migration -- the same
  # never-crash-on-defensive-fallback instinct as
  # flip_finder_live.ex's parse_enabled_techniques/2.
  defp backfill_categories do
    rows =
      repo().all(
        from(c in "currency",
          select: %{id: c.id, external_id: c.external_id, category: c.category}
        )
      )

    Enum.each(rows, fn row ->
      category = resolve_category(row.external_id, row.category)

      if Atom.to_string(category) != row.category do
        repo().update_all(
          from(c in "currency", where: c.id == ^row.id),
          set: [category: Atom.to_string(category)]
        )
      end
    end)
  end

  defp resolve_category(external_id, "divination_card"),
    do: external_id |> GggItemIconGateway.lookup_item() |> category_or(:cards)

  defp resolve_category(external_id, _currency),
    do: external_id |> GggItemIconGateway.lookup_item() |> category_or(:currency)

  defp category_or(%{category: category}, _fallback), do: category
  defp category_or(nil, fallback), do: fallback
end
