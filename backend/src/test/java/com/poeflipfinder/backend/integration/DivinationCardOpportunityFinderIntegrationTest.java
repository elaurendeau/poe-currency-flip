package com.poeflipfinder.backend.integration;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.FlipOpportunity;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.entity.Technique;
import com.poeflipfinder.backend.framework.divinationcard.BundledDivinationCardReferenceGateway;
import com.poeflipfinder.backend.framework.exchange.GggExchangeSourceGateway;
import com.poeflipfinder.backend.framework.itemicon.GggItemIconGateway;
import com.poeflipfinder.backend.gateway.CurrencyReferenceGateway;
import com.poeflipfinder.backend.gateway.ExchangeChangeStreamPage;
import com.poeflipfinder.backend.gateway.ExchangeMarketEntry;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesInteractor;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesOutputBoundary;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesRequestModel;
import com.poeflipfinder.backend.usecase.computeflipopportunities.ComputeFlipOpportunitiesResponseModel;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

/**
 * Unlike DivinationCardOpportunityFinderTest (hand-shaped numbers isolating
 * the finder's own logic), this exercises the real pipeline end to end: a
 * saved real Currency Exchange API response, through the real gateway's
 * parsing, through real Currency resolution against the real bundled Item
 * Icons catalog, through the real interactor, into the real finder -- the
 * same "real fixture, real composed stack" pattern already established on
 * the frontend by useLeagueSelection.integration.test.ts.
 *
 * <p>This is the direct regression guard for a real production incident:
 * The Sephirot genuinely trades (~200 Chaos/card, real volume and stock),
 * but DivinationCardOpportunityFinder's pricing math silently dropped it
 * because "card units per 1 Chaos" floors to 0 for an expensive card. A
 * unit test with hand-picked round numbers would never have caught this --
 * only real captured data exposes it, which is exactly why this test uses
 * the real fixture rather than another synthetic one.
 */
class DivinationCardOpportunityFinderIntegrationTest {

    private static final long FIXTURE_CHANGE_ID = 1786150800L;
    private static final String LEAGUE = "Allflame";

    @Test
    void computeFlipOpportunities_realCapturedHour_theSephirotProducesASaneOpportunity() {
        List<ExchangeMarketSnapshot> snapshots = resolveRealSnapshotsForLeague(LEAGUE);
        assertThat(snapshots).as("sanity check: the real fixture must actually resolve some snapshots").isNotEmpty();

        List<FlipOpportunity> opportunities = computeOpportunities(snapshots);

        FlipOpportunity sephirot = opportunities.stream()
                .filter(o -> o.technique() == Technique.DIVINATION_CARD)
                .filter(o -> o.via().get(0).currency().displayName().equals("The Sephirot"))
                .findFirst()
                .orElseThrow(() -> new AssertionError(
                        "The Sephirot produced no opportunity -- this is the exact bug this test guards against"));

        assertThat(sephirot.start().get(0).quantity()).isPositive();
        assertThat(sephirot.via().get(0).quantity()).isEqualTo(11.0); // The Sephirot's real stack size
        assertThat(sephirot.via().get(1).currency().displayName()).isEqualTo("Divine Orb");
        assertThat(sephirot.volume()).isPositive();
        // The real buy price this hour: ~216-217 Chaos/card, not the pre-fix
        // "cards per Chaos" fraction that used to floor to 0 and get dropped.
        assertThat(sephirot.start().get(0).quantity() / sephirot.via().get(0).quantity()).isBetween(180.0, 230.0);
    }

    @Test
    void computeFlipOpportunities_realCapturedHour_computesWithoutExceptionAcrossTheWholeRealDataset() {
        List<ExchangeMarketSnapshot> snapshots = resolveRealSnapshotsForLeague(LEAGUE);

        List<FlipOpportunity> opportunities = computeOpportunities(snapshots);

        assertThat(opportunities).isNotEmpty();
        assertThat(opportunities).allSatisfy(o -> {
            assertThat(Double.isFinite(o.marginPercent())).isTrue();
            assertThat(Double.isFinite(o.profit().quantity())).isTrue();
            assertThat(o.volume()).isGreaterThan(0);
        });
    }

    /** Real parsing (GggExchangeSourceGateway) + real Currency resolution (real bundled Item Icons catalog), filtered to one league. */
    private List<ExchangeMarketSnapshot> resolveRealSnapshotsForLeague(String league) {
        GggExchangeSourceGateway exchangeSourceGateway = new GggExchangeSourceGateway(RestClient.builder());
        ExchangeChangeStreamPage page = exchangeSourceGateway.normalize(fixture(), FIXTURE_CHANGE_ID, false);

        CurrencyReferenceGateway currencyReferenceGateway = new InMemoryCurrencyReferenceGateway(new GggItemIconGateway());
        League placeholderLeague = new League(1L, league, league, false, true);

        List<ExchangeMarketSnapshot> snapshots = new ArrayList<>();
        for (ExchangeMarketEntry entry : page.entries()) {
            if (!league.equals(entry.leagueExternalId())) {
                continue;
            }
            Optional<Currency> currencyA = currencyReferenceGateway.resolveOrCreateCurrency(entry.currencyAExternalId());
            Optional<Currency> currencyB = currencyReferenceGateway.resolveOrCreateCurrency(entry.currencyBExternalId());
            if (currencyA.isEmpty() || currencyB.isEmpty()) {
                continue; // unresolvable item path -- expected/skipped, same as production ingestion
            }
            snapshots.add(new ExchangeMarketSnapshot(
                    null, 1L, placeholderLeague, currencyA.get(), currencyB.get(), entry.snapshotHour(),
                    entry.volumeTradedA(), entry.volumeTradedB(),
                    entry.lowestStockA(), entry.highestStockA(), entry.lowestStockB(), entry.highestStockB(),
                    entry.lowestRatioA(), entry.highestRatioA(), entry.lowestRatioB(), entry.highestRatioB()));
        }
        return snapshots;
    }

    private List<FlipOpportunity> computeOpportunities(List<ExchangeMarketSnapshot> snapshots) {
        SnapshotQueryGateway snapshotQueryGateway = leagueExternalId -> snapshots;
        CapturingOutputBoundary outputBoundary = new CapturingOutputBoundary();
        ComputeFlipOpportunitiesInteractor interactor = new ComputeFlipOpportunitiesInteractor(
                snapshotQueryGateway, new BundledDivinationCardReferenceGateway(), outputBoundary);

        interactor.computeFlipOpportunities(new ComputeFlipOpportunitiesRequestModel(LEAGUE));

        return outputBoundary.captured.opportunities();
    }

    private String fixture() {
        try {
            Path path = Path.of("src/test/resources/fixtures/currency-exchange-hour-response.json");
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static class CapturingOutputBoundary implements ComputeFlipOpportunitiesOutputBoundary {
        private ComputeFlipOpportunitiesResponseModel captured;

        @Override
        public void present(ComputeFlipOpportunitiesResponseModel response) {
            this.captured = response;
        }
    }

    /**
     * Mirrors JpaCurrencyReferenceGateway's cache-or-resolve-via-ItemIconGateway
     * logic exactly, just backed by a HashMap instead of a JPA repository --
     * no DB needed to prove the resolution + computation logic is correct.
     */
    private static class InMemoryCurrencyReferenceGateway implements CurrencyReferenceGateway {
        private final com.poeflipfinder.backend.gateway.ItemIconGateway itemIconGateway;
        private final Map<String, Currency> cache = new HashMap<>();
        private final AtomicLong nextId = new AtomicLong(1);

        InMemoryCurrencyReferenceGateway(com.poeflipfinder.backend.gateway.ItemIconGateway itemIconGateway) {
            this.itemIconGateway = itemIconGateway;
        }

        @Override
        public Optional<Currency> resolveOrCreateCurrency(String externalId) {
            Currency cached = cache.get(externalId);
            if (cached != null) {
                return Optional.of(cached);
            }
            return itemIconGateway.lookupItem(externalId).map(resolved -> {
                Currency withId = new Currency(
                        nextId.getAndIncrement(), resolved.externalId(), resolved.displayName(),
                        resolved.iconUrl(), resolved.itemType());
                cache.put(externalId, withId);
                return withId;
            });
        }
    }
}
