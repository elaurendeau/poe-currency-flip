defmodule PoeFlipFinder.HistoricalInvestmentPresenter do
  @moduledoc """
  Pure display formatting for docs/PRD.md § 7.14 Feature N -- kept out of
  the `.heex` template per docs/CODE_STYLE.md's Humble Object rule for
  LiveView.
  """

  alias PoeFlipFinder.{HistoricalInvestment, HistoricalPricePattern}

  @doc """
  Applies the shared category-drawer filter (docs/PRD.md § 7.13 Feature M)
  and sorts by the "Next day" horizon -- the same filter+sort split
  `FlipOpportunityTablePresenter.build_display_groups/2` uses for the
  other two tabs, kept out of the `.heex` template per the Humble Object
  rule.
  """
  @spec build_display_list([HistoricalInvestment.candidate()], %{
          enabled_categories: %{atom() => boolean()},
          sort_direction: :asc | :desc
        }) :: [HistoricalInvestment.candidate()]
  def build_display_list(candidates, %{
        enabled_categories: enabled_categories,
        sort_direction: sort_direction
      }) do
    candidates
    |> Enum.filter(&Map.get(enabled_categories, &1.pattern.currency.category, true))
    |> HistoricalInvestment.sort_by_horizon(:day_1, sort_direction)
  end

  @doc "Chaos amounts round to 2 decimals and drop trailing zeros -- '3c', '0.09c', '117.5c', never '117.50c'."
  @spec format_chaos(number()) :: String.t()
  def format_chaos(amount) do
    rounded = Float.round(amount * 1.0, 2)

    text =
      if rounded == trunc(rounded) * 1.0,
        do: Integer.to_string(trunc(rounded)),
        else:
          rounded |> Float.to_string() |> String.trim_trailing("0") |> String.trim_trailing(".")

    text <> "c"
  end

  @doc "Signed percentage, e.g. '+200%', '-11%'."
  @spec format_gain_pct(number()) :: String.t()
  def format_gain_pct(pct) do
    sign = if pct >= 0, do: "+", else: ""
    "#{sign}#{round(pct)}%"
  end

  @spec format_live_price(HistoricalInvestment.live_price()) :: String.t()
  def format_live_price({:ok, price}), do: format_chaos(price) <> " live"
  def format_live_price(:no_live_market), do: "no live market for this category"
  def format_live_price(:not_traded_this_refresh), do: "not traded this refresh"

  @doc "'Day 2, 14h in', or the unknown-start fallback -- never a guessed value."
  @spec format_elapsed_badge({:ok, HistoricalInvestment.elapsed()} | :unknown) :: String.t()
  def format_elapsed_badge({:ok, %{days: days, hours_into_day: hours}}),
    do: "Day #{days}, #{hours}h in"

  def format_elapsed_badge(:unknown), do: "league start time unknown"

  @doc "Column header text for a horizon key, docs/PRD.md § 7.14."
  @spec horizon_label(HistoricalInvestment.horizon_key()) :: String.t()
  def horizon_label(:day_1), do: "Next day"
  def horizon_label(:day_3), do: "Next 3 days"
  def horizon_label(:week_1), do: "Next week"
  def horizon_label(:week_2), do: "Next 2 weeks"

  @doc "'—' for a horizon with no real data at that offset, never a fabricated value."
  @spec format_horizon_chaos(HistoricalInvestment.horizon_value() | nil) :: String.t()
  def format_horizon_chaos(nil), do: "—"
  def format_horizon_chaos(%{chaos: chaos}), do: format_chaos(chaos)

  @spec format_horizon_gain(HistoricalInvestment.horizon_value() | nil) :: String.t()
  def format_horizon_gain(nil), do: ""
  def format_horizon_gain(%{gain_pct: pct}), do: format_gain_pct(pct)

  @type sparkline :: %{
          width: pos_integer(),
          height: pos_integer(),
          points_attr: String.t(),
          marker: %{x: float(), y: float()} | nil
        }

  @doc """
  Normalized SVG coordinates for a candidate's trajectory graph, per
  docs/PRD.md § 7.14: Y is chaos value, X is league day, with a marker at
  `today_day`'s position. Pure geometry only -- the `.heex` template
  builds the actual `<svg>`/`<polyline>`/`<circle>` markup from this, per
  the Humble Object rule. `nil` when there aren't at least two points to
  draw a line between.
  """
  @spec sparkline(
          [HistoricalPricePattern.DayPrice.t()],
          non_neg_integer(),
          pos_integer(),
          pos_integer()
        ) ::
          sparkline() | nil
  def sparkline(trajectory, today_day, width \\ 72, height \\ 26)

  def sparkline(trajectory, _today_day, _width, _height) when length(trajectory) < 2, do: nil

  def sparkline(trajectory, today_day, width, height) do
    padding = 2.0
    days = Enum.map(trajectory, & &1.day)
    chaoses = Enum.map(trajectory, & &1.chaos)
    min_day = Enum.min(days)
    day_span = max(Enum.max(days) - min_day, 1)
    min_chaos = Enum.min(chaoses)
    max_chaos = Enum.max(chaoses)
    chaos_span = if max_chaos == min_chaos, do: 1.0, else: (max_chaos - min_chaos) * 1.0

    to_xy = fn point ->
      x = padding + (point.day - min_day) / day_span * (width - 2 * padding)
      y = height - padding - (point.chaos - min_chaos) / chaos_span * (height - 2 * padding)
      {round1(x), round1(y)}
    end

    coords = Enum.map(trajectory, to_xy)
    points_attr = Enum.map_join(coords, " ", fn {x, y} -> "#{x},#{y}" end)

    marker =
      case Enum.find(trajectory, &(&1.day == today_day)) do
        nil -> nil
        today_point -> today_point |> to_xy.() |> then(fn {x, y} -> %{x: x, y: y} end)
      end

    %{width: width, height: height, points_attr: points_attr, marker: marker}
  end

  defp round1(n), do: Float.round(n * 1.0, 1)
end
