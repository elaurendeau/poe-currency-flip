package com.poeflipfinder.backend.usecase.computeflipopportunities;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.entity.Technique;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class BulkBuyOpportunityFinderTest {

    private static final Instant NOW = Instant.parse("2026-08-06T12:00:00Z");

    private final League league = new League(1L, "Standard", "Standard", false, true);
    private final Currency chaos =
            new Currency(1L, "Metadata/Items/Currency/CurrencyRerollRare", "Chaos Orb", null, Currency.ItemType.CURRENCY);
    private final Currency divine =
            new Currency(2L, "Metadata/Items/Currency/CurrencyModValues", "Divine Orb", null, Currency.ItemType.CURRENCY);
    private final Currency deck = new Currency(
            3L, "Metadata/Items/DivinationCards/DivinationCardStackedDeck", "Stacked Deck", null,
            Currency.ItemType.DIVINATION_CARD);
    private final Currency wisdom = new Currency(
            4L, "Metadata/Items/Currency/CurrencyIdentification", "Scroll of Wisdom", null, Currency.ItemType.CURRENCY);

    private final BulkBuyOpportunityFinder finder = new BulkBuyOpportunityFinder();
    private final DivineChaosRate rate210 = new DivineChaosRate(chaos, divine, 210.0);

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
    void find_bothDirectionsViable_producesTwoOpportunitiesWithHandVerifiedNumbers() {
        // Chaos-deck leg: priceAtLowest=8, priceAtHighest=13 -> buy=floor(13)-1=12, sell=floor(8)+1=9.
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, deck, 1, 8, 1, 13, 100, 50, 1, 1);
        // Divine-deck leg: priceAtLowest=1700, priceAtHighest=1900 -> buy=1899, sell=1701.
        ExchangeMarketSnapshot divineLeg = snapshot(divine, deck, 1, 1700, 1, 1900, 30, 80, 1, 1);

        List<FlipOpportunity> opportunities = finder.find(List.of(chaosLeg, divineLeg), rate210);

        assertThat(opportunities).hasSize(2);
        FlipOpportunity chaosToDivine =
                opportunities.stream().filter(o -> o.sell().get(0).currency().equals(divine)).findFirst().orElseThrow();
        FlipOpportunity divineToChaos =
                opportunities.stream().filter(o -> o.sell().get(0).currency().equals(chaos)).findFirst().orElseThrow();

        // Rescaled so the trade always ends at exactly 1 Divine sold instead
        // of starting from 1 Chaos ("1 Chaos -> 0.005 Divine" is a
        // meaningless fraction to read): via always equals the divine leg's
        // sell price (1701, since that's by definition how much of the
        // intermediary sells for exactly 1 Divine), and start is however
        // much Chaos that took (1701/12 = 141.75). Margin is unaffected
        // (scale-invariant); profit scales up proportionally (0.481481 * 141.75 = 68.25).
        assertThat(chaosToDivine.technique()).isEqualTo(Technique.BULK_BUY);
        assertThat(chaosToDivine.start().get(0).currency()).isEqualTo(chaos);
        assertThat(chaosToDivine.start().get(0).quantity()).isCloseTo(141.75, within(0.001));
        assertThat(chaosToDivine.via().get(0).currency()).isEqualTo(deck);
        assertThat(chaosToDivine.via().get(0).quantity()).isEqualTo(1701.0);
        assertThat(chaosToDivine.sell().get(0).quantity()).isEqualTo(1.0);
        assertThat(chaosToDivine.marginPercent()).isCloseTo(13.0 / 27 * 100, within(0.001));
        assertThat(chaosToDivine.profit().currency()).isEqualTo(chaos);
        assertThat(chaosToDivine.profit().quantity()).isCloseTo(68.25, within(0.001));
        assertThat(chaosToDivine.volume()).isEqualTo(30); // min(chaos buyLegStock=50, divine sellLegStock=30)

        assertThat(divineToChaos.start().get(0).currency()).isEqualTo(divine);
        assertThat(divineToChaos.start().get(0).quantity()).isEqualTo(1.0);
        assertThat(divineToChaos.via().get(0).quantity()).isEqualTo(1899.0);
        assertThat(divineToChaos.sell().get(0).quantity()).isCloseTo(211.0, within(1e-7));
        assertThat(divineToChaos.marginPercent()).isCloseTo(100.0 / 210, within(0.001));
        assertThat(divineToChaos.profit().currency()).isEqualTo(chaos);
        assertThat(divineToChaos.profit().quantity()).isCloseTo(1.0, within(1e-7));
        assertThat(divineToChaos.volume()).isEqualTo(80); // min(divine buyLegStock=80, chaos sellLegStock=100)
    }

    @Test
    void find_chaosBuyLegNotViable_onlyDivineToChaosDirectionSurvives() {
        // Chaos-wisdom leg: priceAtLowest=1, priceAtHighest=1.5 -> buy floors to 0 (invalid),
        // but sell=floor(1)+1=2 is still valid -- this is exactly the asymmetry
        // UndercutQuote exists to expose: a naive "drop both legs if either
        // quote is unusable" would incorrectly return 0 opportunities here.
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, wisdom, 2, 2, 2, 3, 40, 70, 1, 1);
        ExchangeMarketSnapshot divineLeg = snapshot(divine, wisdom, 1, 50, 1, 80, 30, 80, 1, 1);

        List<FlipOpportunity> opportunities = finder.find(List.of(chaosLeg, divineLeg), rate210);

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(divine);
        assertThat(opportunity.sell().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.via().get(0).quantity()).isEqualTo(79.0); // floor(80)-1
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(39.5, within(1e-7)); // 79/2
    }

    @Test
    void find_rateUnavailable_returnsEmptyRegardlessOfSnapshots() {
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, deck, 1, 8, 1, 13, 100, 50, 1, 1);
        ExchangeMarketSnapshot divineLeg = snapshot(divine, deck, 1, 1700, 1, 1900, 30, 80, 1, 1);

        assertThat(finder.find(List.of(chaosLeg, divineLeg), null)).isEmpty();
    }

    @Test
    void find_noMatchingDivineLegForTheSameIntermediary_isNotACandidate() {
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, deck, 1, 8, 1, 13, 100, 50, 1, 1);

        assertThat(finder.find(List.of(chaosLeg), rate210)).isEmpty();
    }

    @Test
    void find_onlyTheChaosDivineReferencePairItself_excludesItAsACandidate() {
        ExchangeMarketSnapshot chaosDivine = snapshot(chaos, divine, 210, 1, 210, 1, 50, 60, 50, 60);

        assertThat(finder.find(List.of(chaosDivine), rate210)).isEmpty();
    }

    @Test
    void find_nonFiniteRatioOnOneLeg_dropsThatIntermediaryEntirely() {
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, deck, 0, 8, 1, 13, 100, 50, 1, 1); // lowestRatioA=0
        ExchangeMarketSnapshot divineLeg = snapshot(divine, deck, 1, 1700, 1, 1900, 30, 80, 1, 1);

        assertThat(finder.find(List.of(chaosLeg, divineLeg), rate210)).isEmpty();
    }
}
