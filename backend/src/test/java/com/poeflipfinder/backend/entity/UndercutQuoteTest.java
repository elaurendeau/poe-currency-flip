package com.poeflipfinder.backend.entity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import java.util.Optional;
import org.junit.jupiter.api.Test;

class UndercutQuoteTest {

    @Test
    void resolve_chaosWisdomWorkedExample_matchesHandVerifiedFeatureBNumbers() {
        // Cross-checks the exact worked example ComputeFlipOpportunitiesInteractorTest
        // validates: raw extremes 185/366 -> buy floors to 366 then undercuts to
        // 365, suggestedSellPrice (Feature B's round-trip-favorable extreme)
        // floors to 185 then undercuts to 186.
        Optional<UndercutQuote> quote = UndercutQuote.resolve(1, 185, 1, 366, 50, 60);

        assertThat(quote).isPresent();
        assertThat(quote.get().suggestedBuyPrice()).contains(365.0);
        assertThat(quote.get().suggestedSellPrice()).isEqualTo(186.0);
        // marketSellPrice (Bulk Buy's one-directional sell reference) is the
        // SAME extreme as the buy price (366), not the round-trip extreme
        // (185) -- a real one-way seller can't rely on the optimistic
        // round-trip rate, so it floors the buy-side extreme with no undercut.
        assertThat(quote.get().marketSellPrice()).isEqualTo(366.0);
        assertThat(quote.get().buyLegStock()).isEqualTo(60); // highestStockStart -- the buy-leg extreme won here
    }

    @Test
    void resolve_buyPriceTooSmallToUndercut_marketSellPriceAlsoCollapses() {
        // marketSellPrice now shares its raw extreme with suggestedBuyPrice
        // (both = the hour's higher "via per start" extreme), so whenever
        // that shared extreme floors below 1, both collapse together: there
        // is no meaningful buy AND no meaningful realistic sell for this leg.
        Optional<UndercutQuote> quote = UndercutQuote.resolve(2, 2, 2, 3, 40, 70);

        assertThat(quote).isPresent();
        assertThat(quote.get().suggestedBuyPrice()).isEmpty();
        assertThat(quote.get().suggestedSellPrice()).isEqualTo(2.0);
        assertThat(quote.get().marketSellPrice()).isEqualTo(1.0); // floor(1.5), same raw extreme as the buy side
        assertThat(quote.get().buyLegStock()).isEqualTo(70);
    }

    @Test
    void resolve_nonFiniteRatio_wholeQuoteIsEmpty() {
        Optional<UndercutQuote> quote = UndercutQuote.resolve(0, 185, 1, 366, 50, 60);

        assertThat(quote).isEmpty();
    }

    @Test
    void resolve_tiedExtremes_undercutsBothLegsAwayFromTheTiedRate() {
        // Cross-checks the existing tied-extremes Feature B test's implied
        // intermediate values: 184/186 - 1 =~ -0.010753 profit, ~-1.0753% margin.
        Optional<UndercutQuote> quote = UndercutQuote.resolve(1, 185, 1, 185, 50, 60);

        assertThat(quote).isPresent();
        assertThat(quote.get().suggestedBuyPrice()).contains(184.0);
        assertThat(quote.get().suggestedSellPrice()).isEqualTo(186.0);
        assertThat(quote.get().marketSellPrice()).isEqualTo(185.0); // extremes tied, so same value either way
    }

    @Test
    void resolve_wideSpreadBetweenExtremes_marketSellPriceUsesTheWorseOneForASeller() {
        // Regression test for a real production bug: a currency (e.g. Orb of
        // Fusing) with a wide in-hour spread against Chaos -- say 9 fusing:1c
        // at one extreme and 17 fusing:1c at the other. The realistic sell
        // reference must be 17 (fewer chaos back per fusing sold -- the worse
        // deal for a seller), not 9 (which is only valid as the OTHER leg of
        // a same-pair round trip, per Feature B). Using 9 here previously
        // made Bulk Buy report an "impossible" sell rate roughly double the
        // worst real one, inflating margin and profit accordingly.
        Optional<UndercutQuote> quote = UndercutQuote.resolve(1, 17, 1, 9, 100, 200);

        assertThat(quote).isPresent();
        assertThat(quote.get().suggestedBuyPrice()).contains(16.0); // floor(17)-1, the favorable-for-buying extreme
        assertThat(quote.get().marketSellPrice()).isEqualTo(17.0); // same extreme as buy, not the optimistic 9
    }
}
