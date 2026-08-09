defmodule PoeFlipFinder.Gateways.BundledVendorRecipeReferenceGatewayTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.BundledVendorRecipeReferenceGateway

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: the real bundled
  # vendor-recipes.json in, asserted normalized VendorRecipe structs out.

  test "loads the real bundled catalog resource without needing normalize/1 first" do
    # Deliberately calls the zero-arg find_all/0, which goes through the
    # real ensure_loaded/0 path -- only passes if
    # priv/reference-data/vendor-recipes.json is present and parses.
    recipes = BundledVendorRecipeReferenceGateway.find_all()

    assert length(recipes) == 18

    recipe =
      Enum.find(recipes, fn r ->
        r.input_currency.display_name == "Portal Scroll" and
          r.output_currency.display_name == "Orb of Transmutation"
      end)

    assert recipe.input_quantity == 7
    assert recipe.output_quantity == 1
    assert recipe.input_currency.external_id == nil
    assert recipe.input_currency.category == :currency
  end

  test "captures both directions of the Armourer's Scrap / Blacksmith's Whetstone loop" do
    recipes = BundledVendorRecipeReferenceGateway.find_all()

    up =
      Enum.find(recipes, fn r ->
        r.input_currency.display_name == "Armourer's Scrap" and
          r.output_currency.display_name == "Blacksmith's Whetstone"
      end)

    down =
      Enum.find(recipes, fn r ->
        r.input_currency.display_name == "Blacksmith's Whetstone" and
          r.output_currency.display_name == "Armourer's Scrap"
      end)

    assert up.input_quantity == 3
    assert down.input_quantity == 1
  end

  test "normalize/1 maps raw JSON fields onto VendorRecipe" do
    raw = [
      %{
        "inputCurrencyName" => "Orb of Alteration",
        "inputQuantity" => 2,
        "outputCurrencyName" => "Jeweller's Orb",
        "outputQuantity" => 1
      }
    ]

    [recipe] = BundledVendorRecipeReferenceGateway.normalize(raw)

    assert recipe.input_currency.display_name == "Orb of Alteration"
    assert recipe.input_currency.category == :currency
    assert recipe.input_quantity == 2
    assert recipe.output_currency.display_name == "Jeweller's Orb"
    assert recipe.output_quantity == 1
  end
end
