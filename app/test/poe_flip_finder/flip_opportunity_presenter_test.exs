defmodule PoeFlipFinder.FlipOpportunityPresenterTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.FlipOpportunityPresenter

  # Ported 1:1 from flipOpportunityPresenter.test.ts.

  describe "classify_margin/1" do
    # Provisional threshold (docs/TECH_STACK.md notes this is TBD once real
    # data ranges are visible -- the mockup's own four example rows don't
    # encode a consistent margin-based rule).
    test "classifies margins at or above 50% as :up" do
      assert FlipOpportunityPresenter.classify_margin(97.84) == :up
      assert FlipOpportunityPresenter.classify_margin(50) == :up
    end

    test "classifies margins below 50% as :mid" do
      assert FlipOpportunityPresenter.classify_margin(49.9) == :mid
      assert FlipOpportunityPresenter.classify_margin(7) == :mid
    end
  end

  describe "format_margin/1" do
    test "formats a positive margin with a + sign and rounds to a whole percent" do
      assert FlipOpportunityPresenter.format_margin(97.84) == %{text: "+98%", color_class: :up}
    end

    test "formats a small margin as :mid" do
      assert FlipOpportunityPresenter.format_margin(7.2) == %{text: "+7%", color_class: :mid}
    end

    test "formats a zero margin without a sign issue" do
      assert FlipOpportunityPresenter.format_margin(0) == %{text: "+0%", color_class: :mid}
    end
  end

  describe "format_profit/2" do
    test "formats profit to 2 decimal places with a + sign, colored by margin" do
      assert FlipOpportunityPresenter.format_profit(0.9784, 97.84) == %{
               text: "+0.98",
               color_class: :up
             }
    end

    test "colors profit :mid when the margin is below the threshold, regardless of profit size" do
      assert FlipOpportunityPresenter.format_profit(14, 7) == %{text: "+14.00", color_class: :mid}
    end
  end

  describe "format_volume/1" do
    test "abbreviates thousands as k with one decimal, trimming a trailing .0" do
      assert FlipOpportunityPresenter.format_volume(1234) == "1.2k"
      assert FlipOpportunityPresenter.format_volume(2000) == "2k"
    end

    test "abbreviates millions as M" do
      assert FlipOpportunityPresenter.format_volume(1_500_000) == "1.5M"
    end

    test "leaves sub-1000 volumes as a plain rounded number" do
      assert FlipOpportunityPresenter.format_volume(999) == "999"
      assert FlipOpportunityPresenter.format_volume(54) == "54"
    end
  end

  describe "format_quantity/1" do
    test "shows exact integers without the ~ prefix" do
      assert FlipOpportunityPresenter.format_quantity(1) == "1"
      assert FlipOpportunityPresenter.format_quantity(366) == "366"
    end

    test "shows non-integers with the ~ prefix, rounded to 2 decimals, trimming trailing zeros" do
      assert FlipOpportunityPresenter.format_quantity(1.9784) == "≈1.98"
      assert FlipOpportunityPresenter.format_quantity(1.999) == "≈2"
    end
  end
end
