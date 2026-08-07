package com.poeflipfinder.backend.usecase.computeflipopportunities;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.Mockito.when;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ComputeFlipOpportunitiesInteractorTest {

    private static final Instant NOW = Instant.parse("2026-08-06T12:00:00Z");

    @Mock
    private SnapshotQueryGateway snapshotQueryGateway;

    @Mock
    private ComputeFlipOpportunitiesOutputBoundary outputBoundary;

    private final League league = new League(1L, "Standard", "Standard", false, true);
    private final Currency chaos =
            new Currency(1L, "Metadata/Items/Currency/CurrencyRerollRare", "Chaos Orb", null, Currency.ItemType.CURRENCY);
    private final Currency wisdom = new Currency(
            2L, "Metadata/Items/Currency/CurrencyIdentification", "Scroll of Wisdom", null, Currency.ItemType.CURRENCY);
    private final Currency divine =
            new Currency(3L, "Metadata/Items/Currency/CurrencyModValues", "Divine Orb", null, Currency.ItemType.CURRENCY);
    private final Currency portal =
            new Currency(4L, "Metadata/Items/Currency/CurrencyPortal", "Portal Scroll", null, Currency.ItemType.CURRENCY);

    private ComputeFlipOpportunitiesInteractor interactor() {
        return new ComputeFlipOpportunitiesInteractor(snapshotQueryGateway, outputBoundary);
    }

    private ExchangeMarketSnapshot snapshot(
            Currency currencyA,
            Currency currencyB,
            double lowestRatioA,
            double lowestRatioB,
            double highestRatioA,
            double highestRatioB) {
        return snapshot(currencyA, currencyB, lowestRatioA, lowestRatioB, highestRatioA, highestRatioB, 50, 60, 50, 60);
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

    private List<FlipOpportunity> compute() {
        interactor().computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel("Standard"));
        ArgumentCaptor<ComputeFlipOpportunitiesResponseModel> captor =
                ArgumentCaptor.forClass(ComputeFlipOpportunitiesResponseModel.class);
        org.mockito.Mockito.verify(outputBoundary).present(captor.capture());
        return captor.getValue().opportunities();
    }

    private Optional<FlipOpportunity> byViaCurrency(List<FlipOpportunity> opportunities, Currency via) {
        return opportunities.stream().filter(o -> o.via().get(0).currency().equals(via)).findFirst();
    }

    @Test
    void computeFlipOpportunities_chaosWisdomPair_matchesValidatedWorkedExample() {
        // Regression/contract test: this exact formula was validated by hand
        // against docs/mockups/flip-row-reference.html's own worked example
        // (Chaos<->Wisdom, "instant 185:1c * competitive 366:1c") before
        // being implemented -- see the implementation plan. 1:185 and 1:366
        // are the hour's two observed rate extremes.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 1, 185, 1, 366)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.technique()).isEqualTo(Technique.EXCHANGE_SPREAD);
        assertThat(opportunity.marginPercent()).isCloseTo(97.84, within(0.1));
        assertThat(opportunity.profit().currency()).isEqualTo(chaos);
        assertThat(opportunity.profit().quantity()).isCloseTo(0.9784, within(0.001));
        assertThat(opportunity.start()).hasSize(1);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.start().get(0).quantity()).isEqualTo(1.0);
        assertThat(opportunity.via()).hasSize(1);
        assertThat(opportunity.via().get(0).currency()).isEqualTo(wisdom);
        assertThat(opportunity.via().get(0).quantity()).isCloseTo(366.0, within(0.001));
        assertThat(opportunity.sell()).hasSize(1);
        assertThat(opportunity.sell().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(1.9784, within(0.001));
        assertThat(opportunity.volume()).isEqualTo(60); // highestStockA -- the buy-leg extreme won here
        assertThat(opportunity.detail()).contains("185").contains("366");
    }

    @Test
    void computeFlipOpportunities_chaosInSlotB_stillAnchorsOnChaosWithMatchingResult() {
        // Same real-world rates as the worked example (185/366 wisdom per
        // chaos), just recorded with chaos as currencyB instead of A --
        // GGG's own pair ordering isn't something we control, so the
        // interactor must anchor on whichever slot the base currency is in.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(wisdom, chaos, 185, 1, 366, 1, 10, 20, 50, 60)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.start().get(0).quantity()).isEqualTo(1.0);
        assertThat(opportunity.via().get(0).currency()).isEqualTo(wisdom);
        assertThat(opportunity.via().get(0).quantity()).isCloseTo(366.0, within(0.001));
        assertThat(opportunity.sell().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(1.9784, within(0.001));
        assertThat(opportunity.profit().currency()).isEqualTo(chaos);
        assertThat(opportunity.profit().quantity()).isCloseTo(0.9784, within(0.001));
        // Chaos is currencyB here, so the buy-leg stock must come from the B
        // side (60), not A's (20) -- proves the volume field followed the
        // anchor swap too, not just start/via/sell.
        assertThat(opportunity.volume()).isEqualTo(60);
    }

    @Test
    void computeFlipOpportunities_neitherCurrencyIsChaosOrDivine_isFilteredOut() {
        // PRD.md § 7.2: Exchange Spread must always start/sell in Chaos or
        // Divine -- an arbitrary altcoin-to-altcoin pair isn't a flip a
        // player can meaningfully act on without already holding that
        // specific altcoin.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(wisdom, portal, 1, 4, 1, 4)));

        assertThat(compute()).isEmpty();
    }

    @Test
    void computeFlipOpportunities_chaosAndDivinePairItself_anchorsOnChaosNotDivine() {
        // When both sides of a pair are base currencies (the Chaos<->Divine
        // pair itself), Chaos wins as the anchor since profit is always
        // Chaos-denominated -- no conversion needed for this pair's own
        // profit figure.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(divine, chaos, 1, 200, 1, 210)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        assertThat(opportunities.get(0).start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunities.get(0).via().get(0).currency()).isEqualTo(divine);
        assertThat(opportunities.get(0).profit().currency()).isEqualTo(chaos);
    }

    @Test
    void computeFlipOpportunities_divineAnchoredPair_convertsProfitToChaosUsingTheChaosDivineRate() {
        // Chaos<->Divine reference pair: both extremes agree at exactly 210
        // chaos per divine (210 chaos-side ratio : 1 divine-side ratio), so
        // the averaged rate is unambiguous.
        ExchangeMarketSnapshot chaosDivine = snapshot(chaos, divine, 210, 1, 210, 1);
        // Divine-anchored pair: identical shape to the original worked
        // example, but starting from Divine instead of Chaos -- rawProfit is
        // 0.9784 *Divine*, which must become 0.9784 * 210 = 205.464 Chaos.
        ExchangeMarketSnapshot divineWisdom = snapshot(divine, wisdom, 1, 185, 1, 366);
        when(snapshotQueryGateway.findActiveSnapshots("Standard")).thenReturn(List.of(chaosDivine, divineWisdom));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(2);
        FlipOpportunity divineAnchored = byViaCurrency(opportunities, wisdom).orElseThrow();
        assertThat(divineAnchored.start().get(0).currency()).isEqualTo(divine);
        assertThat(divineAnchored.marginPercent()).isCloseTo(97.84, within(0.1)); // unit-agnostic, unaffected by conversion
        assertThat(divineAnchored.profit().currency()).isEqualTo(chaos);
        assertThat(divineAnchored.profit().quantity()).isCloseTo(205.464, within(0.01));
    }

    @Test
    void computeFlipOpportunities_divineAnchoredPair_noChaosDivineRateAvailable_isSkipped() {
        // No Chaos<->Divine snapshot anywhere in the active generation --
        // profit can't be safely normalized to Chaos, so the pair is
        // dropped rather than shown with a misleading unit.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(divine, wisdom, 1, 185, 1, 366)));

        assertThat(compute()).isEmpty();
    }

    @Test
    void computeFlipOpportunities_multiplePairs_oneOpportunityPerPair_noReverseDirection() {
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(
                        snapshot(chaos, wisdom, 1, 185, 1, 366),
                        snapshot(chaos, divine, 1, 200, 1, 210)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(2);
        assertThat(opportunities).extracting(o -> o.via().get(0).currency())
                .containsExactlyInAnyOrder(wisdom, divine);
    }

    @Test
    void computeFlipOpportunities_tiedExtremes_zeroMargin() {
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 1, 185, 1, 185)));

        FlipOpportunity opportunity = compute().get(0);
        assertThat(opportunity.marginPercent()).isCloseTo(0.0, within(0.0001));
        assertThat(opportunity.profit().quantity()).isCloseTo(0.0, within(0.0001));
    }

    @Test
    void computeFlipOpportunities_nonFiniteExtreme_skipsThatSnapshotRatherThanErroring() {
        // lowestRatioA=0 makes priceAtLowest = ratioB/0 = Infinity -- must
        // not surface an Infinity/NaN row to the frontend.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 0, 185, 1, 366)));

        assertThat(compute()).isEmpty();
    }
}
