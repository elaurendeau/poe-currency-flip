defmodule PoeFlipFinder.FlipOpportunityPresenter do
  @moduledoc """
  Formatting for a flip opportunity row (docs/TECH_STACK.md § UI Style,
  docs/mockups/flip-row-reference.html). Pure presentation logic -- no
  business rules here, those live in `PoeFlipFinder.FlipOpportunities` and
  its finders.
  """

  # Provisional -- docs/TECH_STACK.md notes the up/mid color threshold is
  # TBD once real data ranges are visible; the mockup's own four example
  # rows don't encode a single consistent margin-based rule.
  @margin_color_threshold 50

  @type color_class :: :up | :mid

  @spec classify_margin(number()) :: color_class()
  def classify_margin(margin_percent) do
    if margin_percent >= @margin_color_threshold, do: :up, else: :mid
  end

  @spec format_margin(number()) :: %{text: String.t(), color_class: color_class()}
  def format_margin(margin_percent) do
    rounded = round(margin_percent)
    %{text: "#{sign_prefix(rounded)}#{rounded}%", color_class: classify_margin(margin_percent)}
  end

  @spec format_profit(number(), number()) :: %{text: String.t(), color_class: color_class()}
  def format_profit(profit, margin_percent) do
    text = "#{sign_prefix(profit)}#{:erlang.float_to_binary(profit * 1.0, decimals: 2)}"
    %{text: text, color_class: classify_margin(margin_percent)}
  end

  @spec format_volume(number()) :: String.t()
  def format_volume(volume) when volume >= 1_000_000,
    do: "#{trim_trailing_zeros(volume / 1_000_000, 1)}M"

  def format_volume(volume) when volume >= 1000, do: "#{trim_trailing_zeros(volume / 1000, 1)}k"
  def format_volume(volume), do: volume |> round() |> Integer.to_string()

  @spec format_quantity(number()) :: String.t()
  def format_quantity(quantity) do
    if integer_valued?(quantity) do
      quantity |> round() |> Integer.to_string()
    else
      "≈#{trim_trailing_zeros(quantity, 2)}"
    end
  end

  defp sign_prefix(value) when value >= 0, do: "+"
  defp sign_prefix(_value), do: ""

  defp integer_valued?(quantity), do: quantity == trunc(quantity)

  defp trim_trailing_zeros(value, decimals) do
    value
    |> :erlang.float_to_binary(decimals: decimals)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end
end
