defmodule PoeFlipFinder.TimestampPresenter do
  @moduledoc """
  docs/PRD.md § 7.6: an absolute timestamp, not a vague relative time --
  full date, hour, minute, and millisecond. Format matches
  docs/mockups/flip-row-reference.html's `.stamp` exactly
  ("2026-08-05 14:32:07.418"): YYYY-MM-DD HH:MM:SS.mmm, 24-hour, local
  time -- not a locale-dependent shape, and not UTC either (docs/PRD.md
  § 7.11 pins this to *local* time explicitly).

  A server-rendered LiveView has no way to know the browser's timezone on
  its own, unlike the original client-rendered React version -- the
  `utc_offset_minutes` parameter is fed by a JS hook reporting
  `-(new Date().getTimezoneOffset())` on mount (the same value the browser
  itself would have used), not a server-side timezone lookup.
  """

  @doc "Formats `dt` shifted by `utc_offset_minutes` (positive = ahead of UTC, matching JS's own sign convention)."
  @spec format_absolute_timestamp(DateTime.t(), integer()) :: String.t()
  def format_absolute_timestamp(dt, utc_offset_minutes) do
    shifted = DateTime.add(dt, utc_offset_minutes, :minute)
    millisecond = shifted.microsecond |> elem(0) |> div(1000)

    date_part = "#{pad(shifted.year, 4)}-#{pad(shifted.month, 2)}-#{pad(shifted.day, 2)}"

    time_part =
      "#{pad(shifted.hour, 2)}:#{pad(shifted.minute, 2)}:#{pad(shifted.second, 2)}.#{pad(millisecond, 3)}"

    "#{date_part} #{time_part}"
  end

  defp pad(value, width), do: value |> Integer.to_string() |> String.pad_leading(width, "0")
end
