defmodule PoeFlipFinder.TimestampPresenterTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.TimestampPresenter

  # Ported 1:1 from timestampPresenter.ts's implicit contract (no dedicated
  # test file existed on the frontend side -- the format is pinned by
  # docs/PRD.md § 7.6 and docs/mockups/flip-row-reference.html's ".stamp"
  # example instead).

  test "formats an absolute timestamp as YYYY-MM-DD HH:MM:SS.mmm, matching the mockup" do
    dt = ~U[2026-08-05 14:32:07.418000Z]

    assert TimestampPresenter.format_absolute_timestamp(dt, 0) == "2026-08-05 14:32:07.418"
  end

  test "pads single-digit month/day/hour/minute/second and milliseconds" do
    dt = ~U[2026-01-02 03:04:05.006000Z]

    assert TimestampPresenter.format_absolute_timestamp(dt, 0) == "2026-01-02 03:04:05.006"
  end

  test "shifts by the given UTC offset in minutes, matching the browser's local time (docs/PRD.md § 7.6/7.11)" do
    dt = ~U[2026-08-05 14:32:07.418000Z]

    # UTC-5 (five hours behind).
    assert TimestampPresenter.format_absolute_timestamp(dt, -300) == "2026-08-05 09:32:07.418"
  end

  test "a negative offset that crosses midnight rolls the date back too" do
    dt = ~U[2026-08-05 01:00:00.000000Z]

    # UTC-5: 2026-08-05 01:00 UTC -> 2026-08-04 20:00 local.
    assert TimestampPresenter.format_absolute_timestamp(dt, -300) == "2026-08-04 20:00:00.000"
  end

  test "a positive offset that crosses midnight rolls the date forward too" do
    dt = ~U[2026-08-05 23:00:00.000000Z]

    # UTC+9: 2026-08-05 23:00 UTC -> 2026-08-06 08:00 local.
    assert TimestampPresenter.format_absolute_timestamp(dt, 540) == "2026-08-06 08:00:00.000"
  end
end
