defmodule PoeFlipFinder.FlipOpportunityTablePresenter do
  @moduledoc """
  Client-side display logic for the flip opportunity table (docs/PRD.md
  § 7.8/7.9/7.10): technique/threshold filtering, sorting, and
  favorites-grouping. Purely a display concern -- it does not change what
  gets computed, only what's shown and in what order.
  """

  alias PoeFlipFinder.{Currency, FlipOpportunity}

  @type sort_column :: :margin | :profit | :volume
  @type sort_direction :: :asc | :desc
  @type thresholds :: %{optional(sort_column()) => number()}

  defp column_value(:margin, opportunity), do: opportunity.margin_percent
  defp column_value(:profit, opportunity), do: opportunity.profit.quantity
  defp column_value(:volume, opportunity), do: opportunity.volume

  @doc """
  Identifies the trade route (technique + currencies), not the computed
  instance -- per docs/PRD.md § 7.10, favorites must survive a refresh
  even though margin/profit/volume are recomputed fresh every time.
  """
  @spec get_route_key(FlipOpportunity.t()) :: String.t()
  def get_route_key(opportunity) do
    ids = fn amounts -> Enum.map_join(amounts, "+", & &1.currency.external_id) end

    [
      Atom.to_string(opportunity.technique),
      ids.(opportunity.start),
      ids.(opportunity.via),
      ids.(opportunity.sell)
    ]
    |> Enum.join("|")
  end

  @spec filter_by_technique([FlipOpportunity.t()], %{
          optional(FlipOpportunity.technique()) => boolean()
        }) :: [
          FlipOpportunity.t()
        ]
  def filter_by_technique(opportunities, enabled_techniques) do
    Enum.filter(opportunities, &Map.get(enabled_techniques, &1.technique, false))
  end

  @doc """
  A row's category is the last leg of its Via chain -- for every technique
  except Divination Card, Via has exactly one leg, so that's unambiguous.
  Divination Card's Via is `[card, reward]`; the card itself is always
  "Cards" and thus useless as a filter dimension, so the category that
  matters is the reward it gives when turned in -- `List.last/1` picks that
  reward without needing a technique-specific branch.
  """
  @spec filter_by_category([FlipOpportunity.t()], %{optional(Currency.category()) => boolean()}) ::
          [FlipOpportunity.t()]
  def filter_by_category(opportunities, enabled_categories) do
    Enum.filter(opportunities, fn opportunity ->
      category = opportunity.via |> List.last() |> Map.fetch!(:currency) |> Map.fetch!(:category)
      Map.get(enabled_categories, category, false)
    end)
  end

  @spec filter_by_thresholds([FlipOpportunity.t()], thresholds()) :: [FlipOpportunity.t()]
  def filter_by_thresholds(opportunities, thresholds) do
    Enum.filter(opportunities, fn opportunity ->
      Enum.all?(thresholds, fn {column, minimum} ->
        column_value(column, opportunity) >= minimum
      end)
    end)
  end

  @doc """
  Hides rows whose Chaos-normalized starting stake exceeds `max_chaos`
  (docs/PRD.md § 7.9) -- lets a player cap what they're shown to what they
  can actually afford, regardless of whether a row happens to anchor on
  Chaos or Divine. `nil` passes every row through unfiltered.
  """
  @spec filter_by_max_start_chaos([FlipOpportunity.t()], number() | nil) :: [FlipOpportunity.t()]
  def filter_by_max_start_chaos(opportunities, nil), do: opportunities

  def filter_by_max_start_chaos(opportunities, max_chaos) do
    Enum.filter(opportunities, &(&1.start_chaos_equivalent <= max_chaos))
  end

  @spec sort_opportunities([FlipOpportunity.t()], sort_column(), sort_direction()) :: [
          FlipOpportunity.t()
        ]
  def sort_opportunities(opportunities, column, direction) do
    Enum.sort_by(opportunities, &column_value(column, &1), direction)
  end

  @type display_groups :: %{favorites: [FlipOpportunity.t()], others: [FlipOpportunity.t()]}

  @spec partition_favorites([FlipOpportunity.t()], MapSet.t(String.t())) :: display_groups()
  def partition_favorites(opportunities, favorite_route_keys) do
    {favorites, others} =
      Enum.split_with(opportunities, &MapSet.member?(favorite_route_keys, get_route_key(&1)))

    %{favorites: favorites, others: others}
  end

  @type display_options :: %{
          enabled_techniques: %{optional(FlipOpportunity.technique()) => boolean()},
          enabled_categories: %{optional(Currency.category()) => boolean()},
          thresholds: thresholds(),
          max_start_chaos: number() | nil,
          sort_column: sort_column(),
          sort_direction: sort_direction(),
          favorite_route_keys: MapSet.t(String.t())
        }

  @doc "A favorite that no longer passes the technique/category/threshold filters simply disappears from both groups -- no placeholder, per docs/PRD.md § 7.10."
  @spec build_display_groups([FlipOpportunity.t()], display_options()) :: display_groups()
  def build_display_groups(opportunities, options) do
    opportunities
    |> filter_by_technique(options.enabled_techniques)
    |> filter_by_category(options.enabled_categories)
    |> filter_by_thresholds(options.thresholds)
    |> filter_by_max_start_chaos(options.max_start_chaos)
    |> sort_opportunities(options.sort_column, options.sort_direction)
    |> partition_favorites(options.favorite_route_keys)
  end
end
