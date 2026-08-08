package com.poeflipfinder.backend.usecase.computeflipopportunities;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.DivinationCardReward;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.entity.Technique;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class DivinationCardOpportunityFinderTest {

    private static final Instant NOW = Instant.parse("2026-08-06T12:00:00Z");

    private final League league = new League(1L, "Standard", "Standard", false, true);
    private final Currency chaos =
            new Currency(1L, "Metadata/Items/Currency/CurrencyRerollRare", "Chaos Orb", null, Currency.ItemType.CURRENCY);
    private final Currency divine =
            new Currency(2L, "Metadata/Items/Currency/CurrencyModValues", "Divine Orb", null, Currency.ItemType.CURRENCY);
    private final Currency card = new Currency(
            3L, "Metadata/Items/DivinationCards/DivinationCardStackedDeck", "Stacked Deck", null,
            Currency.ItemType.DIVINATION_CARD);
    private final Currency regal =
            new Currency(4L, "Metadata/Items/Currency/CurrencyUpgradeMagicToRare", "Regal Orb", null, Currency.ItemType.CURRENCY);

    private final DivinationCardOpportunityFinder finder = new DivinationCardOpportunityFinder();
    private final DivineChaosRate rate210 = new DivineChaosRate(chaos, divine, 210.0);

    // Name-only placeholder Currency, matching what BundledDivinationCardReferenceGateway produces.
    private Currency placeholder(String name, Currency.ItemType itemType) {
        return new Currency(null, null, name, null, itemType);
    }

    private DivinationCardReward reward(int stackSize, String rewardCurrencyName, int rewardQuantity) {
        return new DivinationCardReward(
                placeholder("Stacked Deck", Currency.ItemType.DIVINATION_CARD),
                stackSize,
                placeholder(rewardCurrencyName, Currency.ItemType.CURRENCY),
                rewardQuantity,
                true);
    }

    private ExchangeMarketSnapshot snapshot(
            Currency currencyA,
            Currency currencyB,
            double lowestRatioA,
            double lowestRatioB,
            double highestRatioA,
            double highestRatioB,
            long lowestStockA,
            long highestStockA,
            long lowestStockB,
            long highestStockB) {
        return new ExchangeMarketSnapshot(
                1L, 999L, league, currencyA, currencyB, NOW, 100, 100,
                lowestStockA, highestStockA, lowestStockB, highestStockB,
                lowestRatioA, highestRatioA, lowestRatioB, highestRatioB);
    }

    @Test
    void find_chaosRewardThroughChaosMarket_producesHandVerifiedOpportunity() {
        // Chaos-card leg: priceAtLowest=8, priceAtHighest=13 -> buy=floor(13)-1=12, buyLegStock=highestStockA=50.
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        DivinationCardReward stackedDeckReward = reward(8, "Chaos Orb", 5);

        List<FlipOpportunity> opportunities = finder.find(List.of(chaosLeg), List.of(stackedDeckReward), rate210);

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.technique()).isEqualTo(Technique.DIVINATION_CARD);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.start().get(0).quantity()).isCloseTo(8.0 / 12, within(1e-6));
        assertThat(opportunity.via()).hasSize(2);
        assertThat(opportunity.via().get(0).currency()).isEqualTo(card);
        assertThat(opportunity.via().get(0).quantity()).isEqualTo(8.0);
        assertThat(opportunity.via().get(1).currency()).isEqualTo(chaos);
        assertThat(opportunity.via().get(1).quantity()).isEqualTo(5.0);
        assertThat(opportunity.sell().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.sell().get(0).quantity()).isEqualTo(5.0);
        double costChaos = 8.0 / 12;
        assertThat(opportunity.marginPercent()).isCloseTo((5.0 - costChaos) / costChaos * 100, within(0.01));
        assertThat(opportunity.profit().currency()).isEqualTo(chaos);
        assertThat(opportunity.profit().quantity()).isCloseTo(5.0 - costChaos, within(1e-6));
        assertThat(opportunity.volume()).isEqualTo(50);
        assertThat(opportunity.detail()).isEqualTo("≈0.08c per card");
    }

    @Test
    void find_rewardInAThirdCurrency_pricedAtMarketRate_notCompetitiveRate() {
        // Same chaos-card buy leg as above (suggestedBuyPrice=12).
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        // Chaos-regal leg: priceAtLowest=2, priceAtHighest=3 -> marketSellPrice=floor(3)=3 (regal per chaos).
        ExchangeMarketSnapshot chaosRegalLeg = snapshot(chaos, regal, 1, 2, 1, 3, 10, 20, 5, 5);
        DivinationCardReward coveted = reward(9, "Regal Orb", 5);

        List<FlipOpportunity> opportunities =
                finder.find(List.of(chaosCardLeg, chaosRegalLeg), List.of(coveted), rate210);

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        double costChaos = 9.0 / 12;
        double resaleChaos = 5.0 / 3; // marketSellPrice (3), NOT a competitive/undercut price
        assertThat(opportunity.via().get(1).currency()).isEqualTo(regal);
        assertThat(opportunity.via().get(1).quantity()).isEqualTo(5.0);
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(resaleChaos, within(1e-6));
        assertThat(opportunity.marginPercent()).isCloseTo((resaleChaos - costChaos) / costChaos * 100, within(0.01));
    }

    @Test
    void find_rewardInDivine_convertsThroughTheAveragedReferenceRate() {
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        DivinationCardReward brothersGift = reward(1, "Divine Orb", 5);

        List<FlipOpportunity> opportunities = finder.find(List.of(chaosCardLeg), List.of(brothersGift), rate210);

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.via().get(1).currency()).isEqualTo(divine);
        assertThat(opportunity.via().get(1).quantity()).isEqualTo(5.0);
        assertThat(opportunity.sell().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(5.0 * 210.0, within(1e-6));
    }

    @Test
    void find_noChaosMarketForCard_fallsBackToDivineBuyLeg() {
        // Divine-card leg: priceAtLowest=1700, priceAtHighest=1900 -> buy=floor(1900)-1=1899, buyLegStock=highestStockA=80.
        ExchangeMarketSnapshot divineLeg = snapshot(divine, card, 1, 1700, 1, 1900, 30, 80, 1, 1);
        DivinationCardReward stackedDeckReward = reward(1, "Chaos Orb", 1);

        List<FlipOpportunity> opportunities = finder.find(List.of(divineLeg), List.of(stackedDeckReward), rate210);

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(divine);
        assertThat(opportunity.start().get(0).quantity()).isCloseTo(1.0 / 1899, within(1e-9));
        assertThat(opportunity.volume()).isEqualTo(80);
    }

    @Test
    void find_noMarketForCardAgainstEitherBaseCurrency_isDropped() {
        DivinationCardReward stackedDeckReward = reward(8, "Chaos Orb", 5);

        assertThat(finder.find(List.of(), List.of(stackedDeckReward), rate210)).isEmpty();
    }

    @Test
    void find_rewardCurrencyHasNoChaosMarketOfItsOwn_isDropped() {
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        DivinationCardReward coveted = reward(9, "Regal Orb", 5); // no chaos<->regal snapshot supplied

        assertThat(finder.find(List.of(chaosCardLeg), List.of(coveted), rate210)).isEmpty();
    }

    @Test
    void find_nonPredictableCard_neverProducesAnOpportunity_evenWithPerfectMarketData() {
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        DivinationCardReward gambleCard = new DivinationCardReward(
                placeholder("Stacked Deck", Currency.ItemType.DIVINATION_CARD), 8, null, 0, false);

        assertThat(finder.find(List.of(chaosCardLeg), List.of(gambleCard), rate210)).isEmpty();
    }

    @Test
    void find_buyLegUndercutCollapsesBelowOne_isDroppedSafelyNoCrash() {
        // priceAtLowest=1, priceAtHighest=1.5 -> buy floors to 0 (invalid); no Divine leg to fall back to.
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 2, 2, 2, 3, 40, 70, 1, 1);
        DivinationCardReward stackedDeckReward = reward(8, "Chaos Orb", 5);

        assertThat(finder.find(List.of(chaosCardLeg), List.of(stackedDeckReward), rate210)).isEmpty();
    }

    @Test
    void find_rewardCurrencyMarketSellPriceCollapsesToZero_isDroppedSafelyNoCrash() {
        // Same shape as the real Bulk Buy production bug: a wide in-hour spread
        // (0.5 vs 0.3) floors marketSellPrice to exactly 0, which would divide
        // rewardQuantity by zero if unguarded.
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        ExchangeMarketSnapshot chaosRegalLeg = snapshot(chaos, regal, 2, 1, 10, 3, 100, 50, 1, 1);
        DivinationCardReward coveted = reward(9, "Regal Orb", 5);

        assertThat(finder.find(List.of(chaosCardLeg, chaosRegalLeg), List.of(coveted), rate210)).isEmpty();
    }

    @Test
    void find_rateUnavailable_returnsEmptyRegardlessOfSnapshots() {
        ExchangeMarketSnapshot chaosCardLeg = snapshot(chaos, card, 1, 8, 1, 13, 100, 50, 1, 1);
        DivinationCardReward stackedDeckReward = reward(8, "Chaos Orb", 5);

        assertThat(finder.find(List.of(chaosCardLeg), List.of(stackedDeckReward), null)).isEmpty();
    }
}
