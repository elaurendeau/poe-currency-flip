package com.poeflipfinder.backend.usecase.runingestioncatchup;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.CurrencyReferenceGateway;
import com.poeflipfinder.backend.gateway.ExchangeChangeStreamPage;
import com.poeflipfinder.backend.gateway.ExchangeMarketEntry;
import com.poeflipfinder.backend.gateway.ExchangeSourceGateway;
import com.poeflipfinder.backend.gateway.IngestionFreshness;
import com.poeflipfinder.backend.gateway.LeagueReferenceGateway;
import com.poeflipfinder.backend.gateway.SnapshotRepositoryGateway;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class RunIngestionCatchupInteractorTest {

    private static final Instant NOW = Instant.parse("2026-08-06T12:00:00Z");
    private static final Clock CLOCK = Clock.fixed(NOW, ZoneOffset.UTC);
    private static final long CURRENT_HOUR = (NOW.getEpochSecond() / 3600) * 3600;

    @Mock
    private ExchangeSourceGateway exchangeSourceGateway;

    @Mock
    private SnapshotRepositoryGateway snapshotRepositoryGateway;

    @Mock
    private CurrencyReferenceGateway currencyReferenceGateway;

    @Mock
    private LeagueReferenceGateway leagueReferenceGateway;

    @Mock
    private RunIngestionCatchupOutputBoundary outputBoundary;

    private final Currency currencyA = new Currency(1L, "A", "Currency A", null, Currency.ItemType.CURRENCY);
    private final Currency currencyB = new Currency(2L, "B", "Currency B", null, Currency.ItemType.CURRENCY);
    private final League league = new League(1L, "Standard", "Standard", false, true);

    private RunIngestionCatchupInteractor interactor(CatchupCapPolicy capPolicy) {
        return new RunIngestionCatchupInteractor(
                exchangeSourceGateway,
                snapshotRepositoryGateway,
                currencyReferenceGateway,
                leagueReferenceGateway,
                outputBoundary,
                CLOCK,
                capPolicy);
    }

    private ExchangeMarketEntry oneEntry() {
        return new ExchangeMarketEntry("Standard", "A", "B", NOW, 1, 2, 3, 4, 5, 6, 1.0, 2.0, 3.0, 4.0);
    }

    @Test
    void runIngestionCatchup_reachesTipBeforeCap_reportsFullyCaughtUp_andCommits() {
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(1000L, null));
        when(snapshotRepositoryGateway.startNewGeneration()).thenReturn(999L);
        when(exchangeSourceGateway.fetchHour(1000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(oneEntry()), 2000L, false));
        when(exchangeSourceGateway.fetchHour(2000L)).thenReturn(new ExchangeChangeStreamPage(List.of(), 2000L, true));
        when(currencyReferenceGateway.resolveOrCreateCurrency("A")).thenReturn(Optional.of(currencyA));
        when(currencyReferenceGateway.resolveOrCreateCurrency("B")).thenReturn(Optional.of(currencyB));
        when(leagueReferenceGateway.resolveOrCreateLeague("Standard")).thenReturn(league);

        interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup();

        verify(snapshotRepositoryGateway).commitGeneration(999L, 2000L);
        verify(snapshotRepositoryGateway, never()).discardGeneration(anyLong());
        verify(outputBoundary).present(new RunIngestionCatchupResponseModel(1, true, 2000L, 0));
    }

    @Test
    void runIngestionCatchup_hitsHourCap_reportsPartialProgress_butStillCommitsAndAdvancesCheckpoint() {
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(1000L, null));
        when(snapshotRepositoryGateway.startNewGeneration()).thenReturn(999L);
        // Never returns atTip -- always another hour available.
        when(exchangeSourceGateway.fetchHour(anyLong())).thenAnswer(invocation -> {
            long requested = invocation.getArgument(0);
            return new ExchangeChangeStreamPage(List.of(oneEntry()), requested + 3600, false);
        });
        when(currencyReferenceGateway.resolveOrCreateCurrency("A")).thenReturn(Optional.of(currencyA));
        when(currencyReferenceGateway.resolveOrCreateCurrency("B")).thenReturn(Optional.of(currencyB));
        when(leagueReferenceGateway.resolveOrCreateLeague("Standard")).thenReturn(league);

        interactor(new CatchupCapPolicy(3, Duration.ofHours(24))).runIngestionCatchup();

        long expectedLastProcessed = 1000L + 3 * 3600;
        verify(snapshotRepositoryGateway).commitGeneration(999L, expectedLastProcessed);
        verify(snapshotRepositoryGateway, never()).discardGeneration(anyLong());
        verify(outputBoundary).present(new RunIngestionCatchupResponseModel(3, false, expectedLastProcessed, 0));
    }

    @Test
    void runIngestionCatchup_unresolvableCurrency_skipsThatPair_continuesRun_reportsSkippedCount() {
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(1000L, null));
        when(snapshotRepositoryGateway.startNewGeneration()).thenReturn(999L);
        when(exchangeSourceGateway.fetchHour(1000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(oneEntry()), 2000L, false));
        when(exchangeSourceGateway.fetchHour(2000L)).thenReturn(new ExchangeChangeStreamPage(List.of(), 2000L, true));
        // Currency A is unresolvable -- currency B and league are never even
        // looked up, since resolution short-circuits on the first failure.
        when(currencyReferenceGateway.resolveOrCreateCurrency("A")).thenReturn(Optional.empty());

        interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup();

        verify(snapshotRepositoryGateway).saveSnapshots(List.of());
        verify(snapshotRepositoryGateway).commitGeneration(999L, 2000L);
        verify(outputBoundary).present(new RunIngestionCatchupResponseModel(1, true, 2000L, 1));
    }

    @Test
    void runIngestionCatchup_sameUnresolvablePairAcrossMultipleHours_countsItOnceNotOncePerHour() {
        // Regression test: reported skip count must reflect distinct
        // unresolvable pairs, not raw per-hour occurrences -- confirmed
        // against real GGG data that the same unresolvable pair recurs in
        // most hours it's active, which had inflated this count massively
        // under a naive per-occurrence tally.
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(1000L, null));
        when(snapshotRepositoryGateway.startNewGeneration()).thenReturn(999L);
        when(exchangeSourceGateway.fetchHour(1000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(oneEntry()), 2000L, false));
        when(exchangeSourceGateway.fetchHour(2000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(oneEntry()), 3000L, false));
        when(exchangeSourceGateway.fetchHour(3000L)).thenReturn(new ExchangeChangeStreamPage(List.of(), 3000L, true));
        when(currencyReferenceGateway.resolveOrCreateCurrency("A")).thenReturn(Optional.empty());

        interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup();

        verify(outputBoundary).present(new RunIngestionCatchupResponseModel(2, true, 3000L, 1));
    }

    @Test
    void runIngestionCatchup_hardFailureMidWalk_discardsGeneration_propagatesException_checkpointUnchanged() {
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(1000L, null));
        when(snapshotRepositoryGateway.startNewGeneration()).thenReturn(999L);
        // First hour succeeds (so a generation actually gets minted) --
        // the failure must happen on a later hour to be "mid walk".
        when(exchangeSourceGateway.fetchHour(1000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(oneEntry()), 2000L, false));
        RuntimeException fetchFailure = new RuntimeException("network exploded");
        when(exchangeSourceGateway.fetchHour(2000L)).thenThrow(fetchFailure);

        assertThatThrownBy(() -> interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup())
                .isSameAs(fetchFailure);

        verify(snapshotRepositoryGateway).discardGeneration(999L);
        verify(snapshotRepositoryGateway, never()).commitGeneration(anyLong(), anyLong());
        verify(outputBoundary, never()).present(any());
    }

    @Test
    void runIngestionCatchup_alreadyCaughtUp_isANoOp_neverTouchesTheActiveGeneration() {
        // Regression test: a refresh call that immediately finds nothing
        // new must not mint/commit an empty generation -- doing so purged
        // the still-good active generation for zero gain against real GGG
        // data (docs/ARCHITECTURE.md § Failure Handling: never replace
        // last-known-good data with worse data).
        when(snapshotRepositoryGateway.readIngestionState())
                .thenReturn(new IngestionFreshness(5000L, Instant.parse("2026-08-06T00:00:00Z")));
        when(exchangeSourceGateway.fetchHour(5000L)).thenReturn(new ExchangeChangeStreamPage(List.of(), 5000L, true));

        interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup();

        verify(snapshotRepositoryGateway, never()).startNewGeneration();
        verify(snapshotRepositoryGateway, never()).commitGeneration(anyLong(), anyLong());
        verify(snapshotRepositoryGateway, never()).discardGeneration(anyLong());
        verify(snapshotRepositoryGateway, never()).saveSnapshots(any());
        verify(outputBoundary).present(new RunIngestionCatchupResponseModel(0, true, 5000L, 0));
    }

    @Test
    void runIngestionCatchup_sameCurrencyPairAcrossMultipleHours_savesOnlyTheLatestOccurrence() {
        // Regression test: exchange_market_snapshot's unique constraint is
        // one row per pair *per generation* (docs/SCHEMA.md), but the same
        // pair routinely reappears across many hours of one walk. Saving
        // per-hour without deduplication hit a real duplicate-key failure
        // against live GGG data.
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(1000L, null));
        when(snapshotRepositoryGateway.startNewGeneration()).thenReturn(999L);
        ExchangeMarketEntry earlierHourEntry =
                new ExchangeMarketEntry("Standard", "A", "B", NOW, 1, 1, 1, 1, 1, 1, 1.0, 1.0, 1.0, 1.0);
        ExchangeMarketEntry laterHourEntry =
                new ExchangeMarketEntry("Standard", "A", "B", NOW, 99, 99, 99, 99, 99, 99, 9.0, 9.0, 9.0, 9.0);
        // Real "at tip" responses never carry entries (docs/DATA_SOURCES.md)
        // -- the later occurrence must be its own normal (non-tip) hour.
        when(exchangeSourceGateway.fetchHour(1000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(earlierHourEntry), 2000L, false));
        when(exchangeSourceGateway.fetchHour(2000L))
                .thenReturn(new ExchangeChangeStreamPage(List.of(laterHourEntry), 3000L, false));
        when(exchangeSourceGateway.fetchHour(3000L)).thenReturn(new ExchangeChangeStreamPage(List.of(), 3000L, true));
        when(currencyReferenceGateway.resolveOrCreateCurrency("A")).thenReturn(Optional.of(currencyA));
        when(currencyReferenceGateway.resolveOrCreateCurrency("B")).thenReturn(Optional.of(currencyB));
        when(leagueReferenceGateway.resolveOrCreateLeague("Standard")).thenReturn(league);

        interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup();

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<ExchangeMarketSnapshot>> captor = ArgumentCaptor.forClass(List.class);
        verify(snapshotRepositoryGateway).saveSnapshots(captor.capture());
        assertThat(captor.getValue()).hasSize(1);
        assertThat(captor.getValue().get(0).volumeTradedA()).isEqualTo(99);
    }

    @Test
    void runIngestionCatchup_noStoredCheckpoint_seedsFromLookbackWindow_notFromGggLaunch() {
        when(snapshotRepositoryGateway.readIngestionState()).thenReturn(new IngestionFreshness(null, null));
        long expectedStart = CURRENT_HOUR - Duration.ofHours(24).toSeconds();
        when(exchangeSourceGateway.fetchHour(expectedStart))
                .thenReturn(new ExchangeChangeStreamPage(List.of(), expectedStart, true));

        interactor(new CatchupCapPolicy(48, Duration.ofHours(24))).runIngestionCatchup();

        // Immediately at tip from that computed starting point, so this is
        // also a no-op -- proves the lookback math without needing any
        // hour to actually contain data.
        verify(exchangeSourceGateway).fetchHour(expectedStart);
        verify(snapshotRepositoryGateway, never()).startNewGeneration();
        verify(outputBoundary).present(new RunIngestionCatchupResponseModel(0, true, expectedStart, 0));
    }
}
