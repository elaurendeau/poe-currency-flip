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
        // 365, sell floors to 185 then undercuts to 186.
        Optional<UndercutQuote> quote = UndercutQuote.resolve(1, 185, 1, 366, 50, 60);

        assertThat(quote).isPresent();
        assertThat(quote.get().suggestedBuyPrice()).contains(365.0);
        assertThat(quote.get().suggestedSellPrice()).isEqualTo(186.0);
        assertThat(quote.get().buyLegStock()).isEqualTo(60); // highestStockStart -- the buy-leg extreme won here
        assertThat(quote.get().sellLegStock()).isEqualTo(50);
    }

    @Test
    void resolve_buyPriceTooSmallToUndercut_buyIsEmptyButSellStillValid() {
        // The key correctness property Bulk Buy depends on: a leg's sell price
        // is always computable once ratios are finite, even when that same
        // leg's buy price can't sustain a -1 undercut (rate floors to <= 1).
        Optional<UndercutQuote> quote = UndercutQuote.resolve(2, 2, 2, 3, 40, 70);

        assertThat(quote).isPresent();
        assertThat(quote.get().suggestedBuyPrice()).isEmpty();
        assertThat(quote.get().suggestedSellPrice()).isEqualTo(2.0);
        assertThat(quote.get().buyLegStock()).isEqualTo(70);
        assertThat(quote.get().sellLegStock()).isEqualTo(40);
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
    }
}
