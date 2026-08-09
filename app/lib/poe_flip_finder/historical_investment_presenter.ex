defmodule PoeFlipFinder.HistoricalInvestmentPresenter do
  @moduledoc """
  Pure display formatting for docs/PRD.md § 7.14 Feature N -- kept out of
  the `.heex` template per docs/CODE_STYLE.md's Humble Object rule for
  LiveView.
  """

  alias PoeFlipFinder.HistoricalInvestment

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

  @doc "'not enough for 1' vs. a formatted unit count, per docs/PRD.md § 7.14's no-fixed-cutoff rule."
  @spec format_units(non_neg_integer()) :: String.t()
  def format_units(0), do: "not enough for 1"
  def format_units(1), do: "1 unit"
  def format_units(units), do: "#{units} units"

  @spec format_live_price(HistoricalInvestment.live_price()) :: String.t()
  def format_live_price({:ok, price}), do: format_chaos(price) <> " live"
  def format_live_price(:no_live_market), do: "no live market for this category"
  def format_live_price(:not_traded_this_refresh), do: "not traded this refresh"

  @doc "'Day 2, 14h in', or the unknown-start fallback -- never a guessed value."
  @spec format_elapsed_badge({:ok, HistoricalInvestment.elapsed()} | :unknown) :: String.t()
  def format_elapsed_badge({:ok, %{days: days, hours_into_day: hours}}),
    do: "Day #{days}, #{hours}h in"

  def format_elapsed_badge(:unknown), do: "league start time unknown"
end
