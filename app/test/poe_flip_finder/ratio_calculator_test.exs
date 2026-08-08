defmodule PoeFlipFinder.RatioCalculatorTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.RatioCalculator

  # Ported 1:1 from the TypeScript ratioCalculatorPresenter.test.ts -- these
  # use cases are already drilled and confirmed traceable to docs/PRD.md
  # § 7.12 (see docs/ELIXIR_TEST_MANIFESTO.md § Use-Case Discovery). One gap
  # found while drilling: § 7.12 said "Closest matches" is "always exactly
  # two rows", which didn't match the existing "drops a zero or negative
  # counterpart" test below -- the PRD bullet was corrected, not the test.

  describe "ratio_value/1" do
    test "parses a colon-separated ratio" do
      assert RatioCalculator.ratio_value("15.5:1") == 15.5
    end

    test "parses a slash-separated ratio" do
      assert RatioCalculator.ratio_value("31/2") == 15.5
    end

    test "treats a bare number as an implicit :1 ratio" do
      assert RatioCalculator.ratio_value("15.5") == 15.5
    end

    test "returns nil for a non-numeric input" do
      assert RatioCalculator.ratio_value("abc") == nil
    end

    test "returns nil for a zero or negative side" do
      assert RatioCalculator.ratio_value("5:0") == nil
      assert RatioCalculator.ratio_value("-5:1") == nil
    end

    test "returns nil for empty input" do
      assert RatioCalculator.ratio_value("") == nil
      assert RatioCalculator.ratio_value("   ") == nil
    end

    test "returns nil for a malformed separator" do
      assert RatioCalculator.ratio_value("1:2:3") == nil
    end
  end

  describe "simplest_integer_ratio/1" do
    test "reduces a terminating decimal to its smallest whole-number pair" do
      assert RatioCalculator.simplest_integer_ratio("15.5:1") == %{left: 31, right: 2}
    end

    test "reduces a bare decimal number the same way" do
      assert RatioCalculator.simplest_integer_ratio("15.5") == %{left: 31, right: 2}
    end

    test "preserves an already-reduced whole-number ratio exactly, avoiding float drift" do
      # 4/3 is a repeating decimal -- dividing it out as a float and
      # re-deriving decimal places from that would corrupt this back to
      # something other than 4:3.
      assert RatioCalculator.simplest_integer_ratio("4:3") == %{left: 4, right: 3}
    end

    test "reduces a non-coprime whole-number ratio" do
      assert RatioCalculator.simplest_integer_ratio("10:4") == %{left: 5, right: 2}
    end

    test "returns nil for invalid input" do
      assert RatioCalculator.simplest_integer_ratio("nonsense") == nil
    end
  end

  describe "nearest_right_for_left/2 and nearest_left_for_right/2" do
    test "round to the nearest integer that keeps the ratio" do
      assert RatioCalculator.nearest_right_for_left(145, 15.5) == 9
      assert RatioCalculator.nearest_left_for_right(9, 15.5) == 140
    end
  end

  describe "format_achieved_ratio/2" do
    test "formats the exact ratio of two whole numbers" do
      assert RatioCalculator.format_achieved_ratio(31, 2) == "15.5"
    end

    test "rounds to 2 decimal places" do
      assert RatioCalculator.format_achieved_ratio(145, 9) == "16.11"
    end

    test "returns nil when the right side is zero" do
      assert RatioCalculator.format_achieved_ratio(5, 0) == nil
    end
  end

  describe "exact_ratio_match?/3" do
    test "is true when the pair lands exactly on the target ratio" do
      assert RatioCalculator.exact_ratio_match?(31, 2, 15.5) == true
    end

    test "is false when rounding produced a different ratio" do
      assert RatioCalculator.exact_ratio_match?(145, 9, 15.5) == false
    end
  end

  describe "closest_ratio_matches/3" do
    test "offers both the round-down and round-up counterpart for a left anchor" do
      assert RatioCalculator.closest_ratio_matches(15.5, :left, 145) == [
               %{left: 145, right: 9, achieved_ratio: "16.11"},
               %{left: 145, right: 10, achieved_ratio: "14.5"}
             ]
    end

    test "offers both the round-down and round-up counterpart for a right anchor" do
      assert RatioCalculator.closest_ratio_matches(15.5, :right, 7) == [
               %{left: 108, right: 7, achieved_ratio: "15.43"},
               %{left: 109, right: 7, achieved_ratio: "15.57"}
             ]
    end

    test "drops a zero or negative counterpart rather than offering a meaningless pair" do
      # 1/15.5 rounds down to 0, which isn't a usable ratio side.
      assert RatioCalculator.closest_ratio_matches(15.5, :left, 1) == [
               %{left: 1, right: 1, achieved_ratio: "1"}
             ]
    end
  end

  describe "nearby_whole_ratio_suggestions/3" do
    test "offers the ceiling and floor whole ratios, holding the left anchor fixed" do
      assert RatioCalculator.nearby_whole_ratio_suggestions(15.5, :left, 145) == [
               %{ratio: 16, left: 145, right: 9},
               %{ratio: 15, left: 145, right: 10}
             ]
    end

    test "offers the ceiling and floor whole ratios, holding the right anchor fixed" do
      assert RatioCalculator.nearby_whole_ratio_suggestions(15.5, :right, 7) == [
               %{ratio: 16, left: 112, right: 7},
               %{ratio: 15, left: 105, right: 7}
             ]
    end

    test "returns no suggestions when the target ratio is already a whole number" do
      assert RatioCalculator.nearby_whole_ratio_suggestions(15, :left, 145) == []
    end
  end
end
