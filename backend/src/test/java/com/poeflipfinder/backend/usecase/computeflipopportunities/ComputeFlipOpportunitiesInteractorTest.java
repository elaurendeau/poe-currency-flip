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
    private final Currency chaos = new Currency(1L, "Metadata/Items/Currency/CurrencyRerollRare", "Chaos Orb", null, Currency.ItemType.CURRENCY);
    private final Currency wisdom = new Currency(2L, "Metadata/Items/Currency/CurrencyIdentification", "Scroll of Wisdom", null, Currency.ItemType.CURRENCY);

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
        return new ExchangeMarketSnapshot(
                1L, 999L, league, currencyA, currencyB, NOW, 100, 100, 50, 60, 50, 60,
                lowestRatioA, highestRatioA, lowestRatioB, highestRatioB);
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

        interactor().computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel("Standard"));

        ArgumentCaptor<ComputeFlipOpportunitiesResponseModel> captor =
                ArgumentCaptor.forClass(ComputeFlipOpportunitiesResponseModel.class);
        org.mockito.Mockito.verify(outputBoundary).present(captor.capture());
        List<FlipOpportunity> opportunities = captor.getValue().opportunities();

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.technique()).isEqualTo(Technique.EXCHANGE_SPREAD);
        assertThat(opportunity.marginPercent()).isCloseTo(97.84, within(0.1));
        assertThat(opportunity.profitInChaos()).isCloseTo(0.9784, within(0.001));
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
    void computeFlipOpportunities_multiplePairs_oneOpportunityPerPair_noReverseDirection() {
        Currency divine = new Currency(3L, "Metadata/Items/Currency/CurrencyModValues", "Divine Orb", null, Currency.ItemType.CURRENCY);
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(
                        snapshot(chaos, wisdom, 1, 185, 1, 366),
                        snapshot(chaos, divine, 1, 200, 1, 210)));

        interactor().computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel("Standard"));

        ArgumentCaptor<ComputeFlipOpportunitiesResponseModel> captor =
                ArgumentCaptor.forClass(ComputeFlipOpportunitiesResponseModel.class);
        org.mockito.Mockito.verify(outputBoundary).present(captor.capture());
        List<FlipOpportunity> opportunities = captor.getValue().opportunities();

        assertThat(opportunities).hasSize(2);
        assertThat(opportunities).extracting(o -> o.via().get(0).currency())
                .containsExactlyInAnyOrder(wisdom, divine);
    }

    @Test
    void computeFlipOpportunities_tiedExtremes_zeroMargin() {
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 1, 185, 1, 185)));

        interactor().computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel("Standard"));

        ArgumentCaptor<ComputeFlipOpportunitiesResponseModel> captor =
                ArgumentCaptor.forClass(ComputeFlipOpportunitiesResponseModel.class);
        org.mockito.Mockito.verify(outputBoundary).present(captor.capture());

        FlipOpportunity opportunity = captor.getValue().opportunities().get(0);
        assertThat(opportunity.marginPercent()).isCloseTo(0.0, within(0.0001));
        assertThat(opportunity.profitInChaos()).isCloseTo(0.0, within(0.0001));
    }

    @Test
    void computeFlipOpportunities_nonFiniteExtreme_skipsThatSnapshotRatherThanErroring() {
        // lowestRatioA=0 makes priceAtLowest = ratioB/0 = Infinity -- must
        // not surface an Infinity/NaN row to the frontend.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 0, 185, 1, 366)));

        interactor().computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel("Standard"));

        ArgumentCaptor<ComputeFlipOpportunitiesResponseModel> captor =
                ArgumentCaptor.forClass(ComputeFlipOpportunitiesResponseModel.class);
        org.mockito.Mockito.verify(outputBoundary).present(captor.capture());

        assertThat(captor.getValue().opportunities()).isEmpty();
    }
}
