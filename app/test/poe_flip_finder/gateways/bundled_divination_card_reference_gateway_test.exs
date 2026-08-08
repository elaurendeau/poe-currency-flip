defmodule PoeFlipFinder.Gateways.BundledDivinationCardReferenceGatewayTest do
  use ExUnit.Case, async: true

  alias PoeFlipFinder.Gateways.BundledDivinationCardReferenceGateway

  # Contract test per docs/ELIXIR_TEST_MANIFESTO.md: the real bundled
  # divination-card-rewards.json in, asserted normalized DivinationCardReward
  # structs out.

  test "loads the real bundled catalog resource without needing normalize/1 first" do
    # Deliberately calls the zero-arg find_all/0, which goes through the
    # real ensure_loaded/0 path -- only passes if
    # priv/reference-data/divination-card-rewards.json is present and parses.
    rewards = BundledDivinationCardReferenceGateway.find_all()

    assert length(rewards) == 57

    reward = Enum.find(rewards, &(&1.card.display_name == "Chaotic Disposition"))
    assert reward.stack_size == 1
    assert reward.reward_currency.display_name == "Chaos Orb"
    assert reward.reward_quantity == 5
    assert reward.predictable == true
    assert reward.card.external_id == nil
    assert reward.card.category == :cards
  end

  test "keeps a non-predictable (gamble) card rather than omitting it, per PRD.md § 7.3" do
    rewards = BundledDivinationCardReferenceGateway.find_all()

    the_doctor = Enum.find(rewards, &(&1.card.display_name == "The Doctor"))

    assert the_doctor.predictable == false
    assert the_doctor.reward_currency == nil
    assert the_doctor.reward_quantity == 0
  end

  test "normalize/1 maps raw JSON fields onto DivinationCardReward" do
    raw = [
      %{
        "cardName" => "The Nurse",
        "stackSize" => 4,
        "rewardCurrencyName" => "Orb of Alchemy",
        "rewardQuantity" => 3,
        "isPredictable" => true
      }
    ]

    [reward] = BundledDivinationCardReferenceGateway.normalize(raw)

    assert reward.card.display_name == "The Nurse"
    assert reward.card.category == :cards
    assert reward.stack_size == 4
    assert reward.reward_currency.display_name == "Orb of Alchemy"
    assert reward.reward_currency.category == :currency
    assert reward.reward_quantity == 3
    assert reward.predictable == true
  end

  test "normalize/1 defaults a missing reward_quantity to 0" do
    raw = [
      %{
        "cardName" => "Rain of Chaos",
        "stackSize" => 6,
        "rewardCurrencyName" => nil,
        "rewardQuantity" => nil,
        "isPredictable" => false
      }
    ]

    [reward] = BundledDivinationCardReferenceGateway.normalize(raw)

    assert reward.reward_quantity == 0
    assert reward.reward_currency == nil
  end
end
