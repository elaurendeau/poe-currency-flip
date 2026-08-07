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
    private final Currency deck = new Currency(
            5L, "Metadata/Items/DivinationCards/DivinationCardStackedDeck", "Stacked Deck", null,
            Currency.ItemType.DIVINATION_CARD);

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
    void computeFlipOpportunities_chaosWisdomPair_undercutsBothLegsBeforeComputingProfit() {
        // Raw observed extremes are 185:1 and 366:1 (Chaos:Wisdom). Per
        // docs/PRD.md § 7.2, the buy leg floors then undercuts by -1
        // (366 -> 365) and the sell leg floors then undercuts by +1
        // (185 -> 186) -- these are the actually-postable prices, not the
        // raw historical extremes.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 1, 185, 1, 366)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.technique()).isEqualTo(Technique.EXCHANGE_SPREAD);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.start().get(0).quantity()).isEqualTo(1.0);
        assertThat(opportunity.via().get(0).currency()).isEqualTo(wisdom);
        assertThat(opportunity.via().get(0).quantity()).isCloseTo(365.0, within(0.001));
        assertThat(opportunity.sell().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(1.962366, within(0.001));
        assertThat(opportunity.marginPercent()).isCloseTo(96.2366, within(0.01));
        assertThat(opportunity.profit().currency()).isEqualTo(chaos);
        assertThat(opportunity.profit().quantity()).isCloseTo(0.962366, within(0.001));
        assertThat(opportunity.volume()).isEqualTo(60); // highestStockA -- the buy-leg extreme won here
        assertThat(opportunity.detail()).isEqualTo("buy 365:1 · sell 186:1");
    }

    @Test
    void computeFlipOpportunities_chaosInSlotB_stillUndercutsCorrectlyAfterAnchorSwap() {
        // Same real-world rates as above, just recorded with chaos as
        // currencyB instead of A -- GGG's own pair ordering isn't something
        // we control, so the interactor must anchor and undercut correctly
        // regardless of which slot the base currency is in.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(wisdom, chaos, 185, 1, 366, 1, 10, 20, 50, 60)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        FlipOpportunity opportunity = opportunities.get(0);
        assertThat(opportunity.start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunity.via().get(0).quantity()).isCloseTo(365.0, within(0.001));
        assertThat(opportunity.sell().get(0).quantity()).isCloseTo(1.962366, within(0.001));
        assertThat(opportunity.profit().quantity()).isCloseTo(0.962366, within(0.001));
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
    void computeFlipOpportunities_buySideCannotSustainTheUndercut_isDropped() {
        // Reference buy rate floors to 1, so undercutting by -1 would go to
        // 0 -- there's no way to post a meaningful buy order here (this is
        // exactly what happens buying Divine Orb with a single Chaos Orb:
        // the raw rate is well under 1).
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 2, 2, 2, 3)));

        assertThat(compute()).isEmpty();
    }

    @Test
    void computeFlipOpportunities_chaosAndDivinePairItself_isDroppedSinceOneChaosCannotBuyAWholeDivine() {
        // A real Chaos<->Divine rate (~210 chaos per divine) means "buying
        // Divine with 1 Chaos" nets a small fraction of a Divine, which
        // can't sustain the -1 undercut -- this pair's own listing is
        // correctly dropped even though Chaos still wins the anchor slot.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(divine, chaos, 1, 200, 1, 210)));

        assertThat(compute()).isEmpty();
    }

    @Test
    void computeFlipOpportunities_chaosAndDivineBothQualify_chaosStillWinsTheAnchorSlot() {
        // Deliberately unrealistic ratios (not a real Chaos/Divine rate) --
        // this test isolates the anchor-preference rule (Chaos beats Divine
        // when both are present) from the undercut-viability question
        // covered by the test above.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(divine, chaos, 1, 1, 3, 1)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        assertThat(opportunities.get(0).start().get(0).currency()).isEqualTo(chaos);
        assertThat(opportunities.get(0).via().get(0).currency()).isEqualTo(divine);
        assertThat(opportunities.get(0).profit().currency()).isEqualTo(chaos);
    }

    @Test
    void computeFlipOpportunities_divineAnchoredPair_convertsProfitToChaosUsingTheChaosDivineRate() {
        // Chaos<->Divine reference pair, used only to derive the rate --
        // its own listing is dropped (see the dedicated test above), but
        // resolveDivineChaosRate reads the raw ratios directly regardless.
        ExchangeMarketSnapshot chaosDivine = snapshot(chaos, divine, 210, 1, 210, 1);
        // Divine-anchored pair: identical raw shape to the Chaos/Wisdom
        // worked example, but starting from Divine instead of Chaos. The
        // undercut math is unit-agnostic (365 wisdom bought, 1.962366
        // *Divine* received back), so the raw profit is 0.962366 Divine,
        // which must become 0.962366 * 210 = 202.0968 Chaos.
        ExchangeMarketSnapshot divineWisdom = snapshot(divine, wisdom, 1, 185, 1, 366);
        when(snapshotQueryGateway.findActiveSnapshots("Standard")).thenReturn(List.of(chaosDivine, divineWisdom));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(1);
        FlipOpportunity divineAnchored = byViaCurrency(opportunities, wisdom).orElseThrow();
        assertThat(divineAnchored.start().get(0).currency()).isEqualTo(divine);
        assertThat(divineAnchored.marginPercent()).isCloseTo(96.2366, within(0.01)); // unit-agnostic, unaffected by conversion
        assertThat(divineAnchored.profit().currency()).isEqualTo(chaos);
        assertThat(divineAnchored.profit().quantity()).isCloseTo(202.0968, within(0.01));
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
                        snapshot(chaos, portal, 1, 36, 1, 140)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).hasSize(2);
        assertThat(opportunities).extracting(o -> o.via().get(0).currency())
                .containsExactlyInAnyOrder(wisdom, portal);
    }

    @Test
    void computeFlipOpportunities_tiedExtremes_undercuttingBothLegsNetsASmallLoss() {
        // With no real spread (both extremes identical), undercutting the
        // buy leg down and the sell leg up costs a little on each side --
        // a small guaranteed loss, not exactly zero. This is the realistic
        // cost of actually getting both legs filled.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 1, 185, 1, 185)));

        FlipOpportunity opportunity = compute().get(0);
        assertThat(opportunity.marginPercent()).isCloseTo(-1.0753, within(0.01));
        assertThat(opportunity.profit().quantity()).isCloseTo(-0.010753, within(0.0001));
    }

    @Test
    void computeFlipOpportunities_nonFiniteExtreme_skipsThatSnapshotRatherThanErroring() {
        // lowestRatioA=0 makes priceAtLowest = ratioB/0 = Infinity -- must
        // not surface an Infinity/NaN row to the frontend.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 0, 185, 1, 366)));

        assertThat(compute()).isEmpty();
    }

    @Test
    void computeFlipOpportunities_mergesExchangeSpreadAndBulkBuyIntoOneList() {
        // Chaos<->Divine reference (chaosPerDivine=210), an Exchange Spread
        // pair (chaos-wisdom), and a Bulk Buy candidate (deck trading
        // against both chaos and divine) -- all three techniques' worth of
        // data feeding one request, proving the Stream.concat wiring rather
        // than just each piece in isolation.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(
                        snapshot(chaos, divine, 210, 1, 210, 1),
                        snapshot(chaos, wisdom, 1, 185, 1, 366),
                        snapshot(chaos, deck, 1, 8, 1, 13),
                        snapshot(divine, deck, 1, 1700, 1, 1900)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).extracting(FlipOpportunity::technique)
                .contains(Technique.EXCHANGE_SPREAD, Technique.BULK_BUY);
        assertThat(opportunities).filteredOn(o -> o.technique() == Technique.BULK_BUY).hasSize(2);
    }

    @Test
    void computeFlipOpportunities_noChaosDivineRate_bulkBuyContributesNothingButExchangeSpreadStillWorks() {
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(
                        snapshot(chaos, wisdom, 1, 185, 1, 366),
                        snapshot(chaos, deck, 1, 8, 1, 13)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).extracting(FlipOpportunity::technique)
                .containsOnly(Technique.EXCHANGE_SPREAD);
    }

    @Test
    void computeFlipOpportunities_zeroVolumeExchangeSpread_isExcluded() {
        // Same chaos-wisdom pair as the undercut test above, but with the buy
        // leg's stock (highestStockA, since 366 is the higher extreme) driven
        // to 0 -- a pair nobody can actually trade against isn't a real
        // opportunity, no matter how attractive its margin looks.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(snapshot(chaos, wisdom, 1, 185, 1, 366, 50, 0, 50, 60)));

        assertThat(compute()).isEmpty();
    }

    @Test
    void computeFlipOpportunities_zeroVolumeBulkBuyLeg_excludesBothDirections() {
        // Chaos-deck leg's buy-side stock (highestStockA, the 13 extreme) is
        // 0. Both Bulk Buy directions now price their chaos-deck leg off that
        // same 13 extreme (marketSellPrice reuses the buy-favorable extreme
        // rather than the round-trip one -- see UndercutQuote), so both
        // Chaos->Divine (buys through this leg) and Divine->Chaos (sells
        // through this leg) are bottlenecked by the same, now-zero, stock
        // figure: min() is symmetric, so there's no fixture where a single
        // leg's stock starves one bulk-buy direction but not the other.
        when(snapshotQueryGateway.findActiveSnapshots("Standard"))
                .thenReturn(List.of(
                        snapshot(chaos, divine, 210, 1, 210, 1),
                        snapshot(chaos, deck, 1, 8, 1, 13, 100, 0, 1, 1),
                        snapshot(divine, deck, 1, 1700, 1, 1900)));

        List<FlipOpportunity> opportunities = compute();

        assertThat(opportunities).filteredOn(o -> o.technique() == Technique.BULK_BUY).isEmpty();
    }
}
