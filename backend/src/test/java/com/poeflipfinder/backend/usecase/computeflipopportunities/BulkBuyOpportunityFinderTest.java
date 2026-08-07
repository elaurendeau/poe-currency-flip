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
        // Chaos-deck leg: priceAtLowest=8, priceAtHighest=13 -> buy=floor(13)-1=12.
        // marketSellPrice = floor(13) = 13 -- the SAME extreme as the buy price
        // (the worse-for-a-seller one), not the round-trip-favorable 8. This is
        // the exact shape of a real production bug: a wide in-hour spread (here
        // 8 vs 13) previously fed the optimistic 8 into a one-directional sell,
        // overstating how much a real seller could get.
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, deck, 1, 8, 1, 13, 100, 50, 1, 1);
        // Divine-deck leg: priceAtLowest=1700, priceAtHighest=1900 -> buy=1899, marketSellPrice=floor(1900)=1900.
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
        // *market* sell price (1900, the worse-for-a-seller real hourly
        // extreme -- same one the buy price is undercut from, floored with no
        // further push), and start is however much Chaos that took
        // (1900/12 = 158.333). Margin is unaffected by the rescaling itself
        // (still scale-invariant); profit scales up proportionally.
        assertThat(chaosToDivine.technique()).isEqualTo(Technique.BULK_BUY);
        assertThat(chaosToDivine.start().get(0).currency()).isEqualTo(chaos);
        assertThat(chaosToDivine.start().get(0).quantity()).isCloseTo(1900.0 / 12, within(0.001));
        assertThat(chaosToDivine.via().get(0).currency()).isEqualTo(deck);
        assertThat(chaosToDivine.via().get(0).quantity()).isEqualTo(1900.0);
        assertThat(chaosToDivine.sell().get(0).quantity()).isEqualTo(1.0);
        assertThat(chaosToDivine.marginPercent()).isCloseTo(31.0 / 95 * 100, within(0.001));
        assertThat(chaosToDivine.profit().currency()).isEqualTo(chaos);
        assertThat(chaosToDivine.profit().quantity()).isCloseTo(155.0 / 3, within(0.001));
        assertThat(chaosToDivine.volume()).isEqualTo(50); // min(chaos buyLegStock=50, divine buyLegStock=80)

        // Divine->Chaos sells through the chaos leg's market price (13, not
        // the round-trip-favorable 8), so 1899 deck / 13 = 146.077 Chaos --
        // below the 210 c/div direct baseline, i.e. this direction is a real
        // loss even though the reverse direction is profitable. Exactly the
        // asymmetry BulkBuyOpportunityFinder's class doc calls out: each
        // direction is evaluated independently, and one being viable says
        // nothing about the other.
        assertThat(divineToChaos.start().get(0).currency()).isEqualTo(divine);
        assertThat(divineToChaos.start().get(0).quantity()).isEqualTo(1.0);
        assertThat(divineToChaos.via().get(0).quantity()).isEqualTo(1899.0);
        assertThat(divineToChaos.sell().get(0).quantity()).isCloseTo(1899.0 / 13, within(1e-7));
        assertThat(divineToChaos.marginPercent()).isCloseTo((1899.0 / 13 - 210) / 210 * 100, within(0.001));
        assertThat(divineToChaos.profit().currency()).isEqualTo(chaos);
        assertThat(divineToChaos.profit().quantity()).isCloseTo(1899.0 / 13 - 210, within(1e-7));
        assertThat(divineToChaos.volume()).isEqualTo(50); // min(divine buyLegStock=80, chaos buyLegStock=50)
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
        // Sells through the chaos leg's market price (1, the floored raw
        // extreme with no +1 push), not the competitive 2 -- 79/1 = 79.
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(79.0, within(1e-7));
    }

    @Test
    void find_chaosLegPriceCollapsesBelowOne_bothDirectionsDroppedSafelyNoCrash() {
        // A real production incident: marketSellPrice (no +1 push, unlike
        // suggestedSellPrice) can floor to exactly 0 when its raw extreme is
        // below 1 -- e.g. both priceAtLowest=0.5 and priceAtHighest=0.3 here.
        // divineToChaos divides by chaosLeg.marketSellPrice(), so an
        // unguarded 0 produces Infinity, which Jackson serializes as the
        // *string* "Infinity" and crashes the frontend's .toFixed() call
        // (blank black screen in production).
        //
        // marketSellPrice now shares its raw extreme with suggestedBuyPrice
        // (see UndercutQuote), so a leg's price collapsing below 1 always
        // takes out BOTH directions that leg participates in together --
        // chaosToDivine via chaosLeg.suggestedBuyPrice() being empty, and
        // divineToChaos via chaosLeg.marketSellPrice() being <= 0 -- rather
        // than exactly one surviving. The guard's job is just to make sure
        // that shows up as zero opportunities, never a crash.
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, wisdom, 2, 1, 10, 3, 100, 50, 1, 1);
        ExchangeMarketSnapshot divineLeg = snapshot(divine, wisdom, 1, 1700, 1, 1900, 30, 80, 1, 1);

        List<FlipOpportunity> opportunities = finder.find(List.of(chaosLeg, divineLeg), rate210);

        assertThat(opportunities).isEmpty();
    }

    @Test
    void find_divineLegPriceCollapsesBelowOne_bothDirectionsDroppedSafelyNoCrash() {
        // Mirror of the case above: chaosToDivine uses divineLeg.marketSellPrice()
        // as its via amount, which feeds into a division against the direct
        // baseline -- an unguarded 0 there produces Infinity in marginPercent
        // even though no field is a literal division by the zero itself.
        ExchangeMarketSnapshot chaosLeg = snapshot(chaos, deck, 1, 8, 1, 13, 100, 50, 1, 1);
        ExchangeMarketSnapshot divineLeg = snapshot(divine, deck, 2, 1, 10, 3, 100, 50, 1, 1);

        List<FlipOpportunity> opportunities = finder.find(List.of(chaosLeg, divineLeg), rate210);

        assertThat(opportunities).isEmpty();
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
