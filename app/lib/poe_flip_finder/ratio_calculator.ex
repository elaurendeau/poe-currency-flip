defmodule PoeFlipFinder.RatioCalculator do
  @moduledoc """
  Pure math backing Feature L, docs/PRD.md § 7.12 -- a standalone helper for
  deriving whole-number trade ratios from a free-form decimal ratio input.
  Entirely client-facing logic, no gateway or persistence involvement.
  """

  @type integer_ratio :: %{left: integer(), right: integer()}
  @type closest_match :: %{left: integer(), right: integer(), achieved_ratio: String.t()}
  @type ratio_suggestion :: %{ratio: integer(), left: integer(), right: integer()}
  @type anchor :: :left | :right

  @doc ~S'Ratio input as a plain number, e.g. "15.5:1" or "31:2" or "15.5" -> 15.5.'
  @spec ratio_value(String.t()) :: float() | nil
  def ratio_value(raw) do
    case split_ratio_text(raw) do
      nil ->
        nil

      {left_text, right_text} ->
        {:ok, left_num} = parse_positive_number(left_text)
        {:ok, right_num} = parse_positive_number(right_text)
        left_num / right_num
    end
  end

  @doc """
  Smallest whole-number pair matching the entered ratio exactly, derived
  from the input's own decimal places rather than a divided-out float --
  avoids precision drift for ratios like 4:3 that don't terminate as a
  decimal.
  """
  @spec simplest_integer_ratio(String.t()) :: integer_ratio() | nil
  def simplest_integer_ratio(raw) do
    case split_ratio_text(raw) do
      nil ->
        nil

      {left_text, right_text} ->
        {:ok, left_num} = parse_positive_number(left_text)
        {:ok, right_num} = parse_positive_number(right_text)
        decimal_places = max(decimal_places_of(left_text), decimal_places_of(right_text))
        scale = round(:math.pow(10, decimal_places))
        scaled_left = round(left_num * scale)
        scaled_right = round(right_num * scale)
        divisor = max(Integer.gcd(scaled_left, scaled_right), 1)
        %{left: div(scaled_left, divisor), right: div(scaled_right, divisor)}
    end
  end

  @spec nearest_right_for_left(number(), number()) :: integer()
  def nearest_right_for_left(left, ratio), do: round(left / ratio)

  @spec nearest_left_for_right(number(), number()) :: integer()
  def nearest_left_for_right(right, ratio), do: round(right * ratio)

  @doc """
  The ratio actually achieved by two whole numbers, for feedback when they
  don't land exactly on the requested ratio (e.g. after rounding to
  nearest).
  """
  @spec format_achieved_ratio(number(), number()) :: String.t() | nil
  def format_achieved_ratio(_left, right) when right == 0, do: nil

  def format_achieved_ratio(left, right) do
    left |> achieved_hundredths(right) |> format_hundredths()
  end

  @doc """
  Whether left/right land exactly on the target ratio, compared at the same
  2-decimal precision `format_achieved_ratio/2` displays -- avoids float
  noise from the two independent divisions (achieved vs. parsed target)
  disagreeing on digits the UI doesn't show anyway.
  """
  @spec exact_ratio_match?(number(), number(), number()) :: boolean()
  def exact_ratio_match?(_left, right, _ratio) when right == 0, do: false

  def exact_ratio_match?(left, right, ratio) do
    achieved_hundredths(left, right) == round(ratio * 100)
  end

  @doc """
  The two whole-number candidates that bracket the target ratio for the
  anchored field -- rounding the counterpart down (overshoots the ratio)
  and up (undershoots it). Always both, never just whichever rounds
  "nearest", since either direction can be the one the player actually
  wants to list at. A rounded-down counterpart that lands at zero (or
  below) is dropped rather than offered as a meaningless pair -- see
  docs/PRD.md § 7.12's "Closest matches" exception.
  """
  @spec closest_ratio_matches(number(), anchor(), number()) :: [closest_match()]
  def closest_ratio_matches(ratio, anchor, anchor_value) do
    quotient = if anchor == :left, do: anchor_value / ratio, else: anchor_value * ratio

    [floor(quotient), ceil(quotient)]
    |> Enum.filter(&(&1 > 0))
    |> Enum.uniq()
    |> Enum.map(fn counterpart ->
      left = if anchor == :left, do: anchor_value, else: counterpart
      right = if anchor == :left, do: counterpart, else: anchor_value
      %{left: left, right: right, achieved_ratio: format_achieved_ratio(left, right) || ""}
    end)
  end

  @doc """
  Alternatives at the nearest whole-number ratios above and below the
  target, holding whichever field the user last edited (the anchor) fixed
  -- lets the user trade exactness for a rounder ratio. Empty when the
  target ratio is already a whole number, since there's nothing nearby to
  offer.
  """
  @spec nearby_whole_ratio_suggestions(number(), anchor(), number()) :: [ratio_suggestion()]
  def nearby_whole_ratio_suggestions(ratio, anchor, anchor_value) do
    floor_ratio = floor(ratio)
    ceil_ratio = ceil(ratio)

    if floor_ratio == ceil_ratio do
      []
    else
      Enum.map([ceil_ratio, floor_ratio], &ratio_suggestion(&1, anchor, anchor_value))
    end
  end

  defp ratio_suggestion(candidate, anchor, anchor_value) do
    left = if anchor == :left, do: anchor_value, else: nearest_left_for_right(anchor_value, candidate)
    right = if anchor == :right, do: anchor_value, else: nearest_right_for_left(anchor_value, candidate)
    %{ratio: candidate, left: left, right: right}
  end

  defp achieved_hundredths(_left, right) when right == 0, do: nil
  defp achieved_hundredths(left, right), do: round(left / right * 100)

  defp format_hundredths(nil), do: nil

  defp format_hundredths(hundredths) do
    whole = div(hundredths, 100)
    frac = rem(hundredths, 100)

    cond do
      frac == 0 -> Integer.to_string(whole)
      rem(frac, 10) == 0 -> "#{whole}.#{div(frac, 10)}"
      true -> "#{whole}.#{frac |> Integer.to_string() |> String.pad_leading(2, "0")}"
    end
  end

  defp split_ratio_text(raw) do
    trimmed = String.trim(raw)

    with true <- trimmed != "",
         parts <- trimmed |> String.split(~r/[:\/]/) |> Enum.map(&String.trim/1),
         true <- length(parts) <= 2 and not Enum.any?(parts, &(&1 == "")),
         left_text <- Enum.at(parts, 0),
         right_text <- if(length(parts) == 2, do: Enum.at(parts, 1), else: "1"),
         {:ok, _left_num} <- parse_positive_number(left_text),
         {:ok, _right_num} <- parse_positive_number(right_text) do
      {left_text, right_text}
    else
      _ -> nil
    end
  end

  defp parse_positive_number(text) do
    case Float.parse(text) do
      {num, ""} when num > 0 -> {:ok, num}
      _ -> parse_positive_integer(text)
    end
  end

  defp parse_positive_integer(text) do
    case Integer.parse(text) do
      {num, ""} when num > 0 -> {:ok, num * 1.0}
      _ -> :error
    end
  end

  defp decimal_places_of(text) do
    case String.split(text, ".", parts: 2) do
      [_int] -> 0
      [_int, frac] -> frac |> String.trim_trailing("0") |> String.length()
    end
  end
end
