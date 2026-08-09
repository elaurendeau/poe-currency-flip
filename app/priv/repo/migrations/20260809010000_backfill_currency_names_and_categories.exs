defmodule PoeFlipFinder.Repo.Migrations.BackfillCurrencyNamesAndCategories do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  alias PoeFlipFinder.Gateways.GggItemIconGateway

  # `currency` rows are created once and never touched again
  # (EctoCurrencyReferenceGateway.resolve_or_create_currency/1: an
  # existing row for a given external_id is returned as-is, the item icon
  # gateway is only ever consulted for a row that doesn't exist yet). That
  # means every improvement to GggItemIconGateway's resolution logic --
  # this project has shipped several in a row (the category taxonomy
  # widening, the Tattoo/Omen/Runegraft patterns, the path-marker
  # classifier, and the Supplementary Currency Names source) -- only ever
  # applies to a *newly-seen* item, never retroactively to a row a
  # previous, less-capable version of this code already persisted.
  # "Refresh market data" walks new hours of the change stream; it can
  # never repair an existing row on its own. This is the one-time
  # backfill that actually does: re-run the current resolver against
  # every existing row's external_id and update display_name/category/
  # icon_url wherever the result differs. Currency is pure cache (see
  # docs/SCHEMA.md "Reference data") -- fully, deterministically
  # re-derivable from external_id + the bundled resources, so this is
  # safe to just overwrite.
  def up do
    rows =
      repo().all(
        from(c in "currency",
          select: %{
            id: c.id,
            external_id: c.external_id,
            display_name: c.display_name,
            icon_url: c.icon_url,
            category: c.category
          }
        )
      )

    Enum.each(rows, &backfill_row/1)
  end

  def down do
    :ok
  end

  defp backfill_row(row) do
    case GggItemIconGateway.lookup_item(row.external_id) do
      nil ->
        :ok

      resolved ->
        category = Atom.to_string(resolved.category)

        if resolved.display_name != row.display_name or resolved.icon_url != row.icon_url or
             category != row.category do
          repo().update_all(
            from(c in "currency", where: c.id == ^row.id),
            set: [
              display_name: resolved.display_name,
              icon_url: resolved.icon_url,
              category: category
            ]
          )
        end
    end
  end
end
