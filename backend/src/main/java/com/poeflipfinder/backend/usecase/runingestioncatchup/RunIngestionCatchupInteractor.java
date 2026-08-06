package com.poeflipfinder.backend.usecase.runingestioncatchup;

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
import java.time.Instant;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Orchestrates one bounded catch-up walk of Currency Exchange ingestion
 * (docs/ARCHITECTURE.md § Currency Exchange Ingestion). Hitting the per-call
 * hour cap is a normal, successful stop -- it still commits what was
 * gathered and reports itself as not fully caught up; only a hard failure
 * from the source gateway discards the generation.
 */
public class RunIngestionCatchupInteractor implements RunIngestionCatchupInputBoundary {

    private final ExchangeSourceGateway exchangeSourceGateway;
    private final SnapshotRepositoryGateway snapshotRepositoryGateway;
    private final CurrencyReferenceGateway currencyReferenceGateway;
    private final LeagueReferenceGateway leagueReferenceGateway;
    private final RunIngestionCatchupOutputBoundary outputBoundary;
    private final Clock clock;
    private final CatchupCapPolicy capPolicy;

    public RunIngestionCatchupInteractor(
            ExchangeSourceGateway exchangeSourceGateway,
            SnapshotRepositoryGateway snapshotRepositoryGateway,
            CurrencyReferenceGateway currencyReferenceGateway,
            LeagueReferenceGateway leagueReferenceGateway,
            RunIngestionCatchupOutputBoundary outputBoundary,
            Clock clock,
            CatchupCapPolicy capPolicy) {
        this.exchangeSourceGateway = exchangeSourceGateway;
        this.snapshotRepositoryGateway = snapshotRepositoryGateway;
        this.currencyReferenceGateway = currencyReferenceGateway;
        this.leagueReferenceGateway = leagueReferenceGateway;
        this.outputBoundary = outputBoundary;
        this.clock = clock;
        this.capPolicy = capPolicy;
    }

    @Override
    public void runIngestionCatchup() {
        long startingChangeId = resolveStartingChangeId();
        ExchangeChangeStreamPage firstPage = exchangeSourceGateway.fetchHour(startingChangeId);

        if (firstPage.atTip()) {
            // Nothing new since the last commit. Minting and activating a
            // new (empty) generation here would purge the still-good active
            // one for zero gain -- never replace last-known-good data with
            // worse data (docs/ARCHITECTURE.md § Failure Handling). A no-op
            // refresh must be a true no-op: the active generation is
            // untouched, and the checkpoint doesn't need to move either,
            // since it's already at this same id.
            outputBoundary.present(new RunIngestionCatchupResponseModel(0, true, startingChangeId, 0));
            return;
        }

        long generationId = snapshotRepositoryGateway.startNewGeneration();
        try {
            CatchupResult result = walkForward(generationId, startingChangeId, firstPage);
            snapshotRepositoryGateway.commitGeneration(generationId, result.lastProcessedChangeId());
            outputBoundary.present(toResponseModel(result));
        } catch (RuntimeException e) {
            snapshotRepositoryGateway.discardGeneration(generationId);
            throw e;
        }
    }

    private CatchupResult walkForward(long generationId, long startingChangeId, ExchangeChangeStreamPage firstPage) {
        long changeId = startingChangeId;
        int hoursProcessed = 0;

        // Scoped to this one call -- cuts redundant DB round-trips across
        // the many repeated appearances of the same currency/league within
        // a single walk, without outliving the request.
        Map<String, Currency> currencyCache = new HashMap<>();
        Map<String, League> leagueCache = new HashMap<>();

        // exchange_market_snapshot's unique constraint is one row per pair
        // *per generation* -- "current market state only" (docs/SCHEMA.md),
        // not one row per hour observed. The same pair routinely reappears
        // across many hours of one walk, so entries are deduplicated here
        // (later hour wins) and saved once, rather than inserted per hour.
        Map<SnapshotKey, ExchangeMarketSnapshot> latestSnapshotByPair = new LinkedHashMap<>();

        // Distinct unresolvable pairs, not a raw per-occurrence count -- the
        // same unresolvable pair reappears every hour it's active, and a
        // count that grows with hours-walked rather than with actual data
        // quality would be a misleading metric (confirmed against real GGG
        // data: a handful of distinct unresolvable pairs, each recurring
        // across most of the walk's hours, inflating a naive counter).
        Set<UnresolvedPairKey> unresolvedPairs = new LinkedHashSet<>();

        ExchangeChangeStreamPage page = firstPage;
        while (hoursProcessed < capPolicy.maxHoursPerCall()) {
            if (page.atTip()) {
                snapshotRepositoryGateway.saveSnapshots(List.copyOf(latestSnapshotByPair.values()));
                return new CatchupResult(changeId, hoursProcessed, unresolvedPairs.size(), true);
            }

            for (ExchangeMarketEntry entry : page.entries()) {
                Optional<ExchangeMarketSnapshot> snapshot =
                        resolveSnapshot(generationId, entry, currencyCache, leagueCache);
                if (snapshot.isPresent()) {
                    latestSnapshotByPair.put(SnapshotKey.of(snapshot.get()), snapshot.get());
                } else {
                    unresolvedPairs.add(UnresolvedPairKey.of(entry));
                }
            }

            hoursProcessed++;
            changeId = page.nextChangeId();
            if (hoursProcessed < capPolicy.maxHoursPerCall()) {
                page = exchangeSourceGateway.fetchHour(changeId);
            }
        }

        snapshotRepositoryGateway.saveSnapshots(List.copyOf(latestSnapshotByPair.values()));
        return new CatchupResult(changeId, hoursProcessed, unresolvedPairs.size(), false);
    }

    private long resolveStartingChangeId() {
        IngestionFreshness freshness = snapshotRepositoryGateway.readIngestionState();
        if (freshness.lastProcessedChangeId() != null) {
            return freshness.lastProcessedChangeId();
        }
        return firstRunStartingChangeId();
    }

    // No stored checkpoint yet -- seed near "now" rather than Currency
    // Exchange's actual launch; old data has no product value (see
    // docs/PRD.md § 4 Non-Goals: no historical trend charts).
    private long firstRunStartingChangeId() {
        long nowEpochSecond = Instant.now(clock).getEpochSecond();
        long currentHourEpochSecond = (nowEpochSecond / 3600) * 3600;
        return currentHourEpochSecond - capPolicy.firstRunLookback().toSeconds();
    }

    private Optional<ExchangeMarketSnapshot> resolveSnapshot(
            long generationId,
            ExchangeMarketEntry entry,
            Map<String, Currency> currencyCache,
            Map<String, League> leagueCache) {
        Optional<Currency> currencyA = resolveCurrency(entry.currencyAExternalId(), currencyCache);
        if (currencyA.isEmpty()) {
            return Optional.empty();
        }
        Optional<Currency> currencyB = resolveCurrency(entry.currencyBExternalId(), currencyCache);
        if (currencyB.isEmpty()) {
            return Optional.empty();
        }
        League league = resolveLeague(entry.leagueExternalId(), leagueCache);

        return Optional.of(new ExchangeMarketSnapshot(
                null,
                generationId,
                league,
                currencyA.get(),
                currencyB.get(),
                entry.snapshotHour(),
                entry.volumeTradedA(),
                entry.volumeTradedB(),
                entry.lowestStockA(),
                entry.highestStockA(),
                entry.lowestStockB(),
                entry.highestStockB(),
                entry.lowestRatioA(),
                entry.highestRatioA(),
                entry.lowestRatioB(),
                entry.highestRatioB()));
    }

    private Optional<Currency> resolveCurrency(String externalId, Map<String, Currency> cache) {
        Currency cached = cache.get(externalId);
        if (cached != null) {
            return Optional.of(cached);
        }
        Optional<Currency> resolved = currencyReferenceGateway.resolveOrCreateCurrency(externalId);
        resolved.ifPresent(currency -> cache.put(externalId, currency));
        return resolved;
    }

    private League resolveLeague(String externalId, Map<String, League> cache) {
        League cached = cache.get(externalId);
        if (cached != null) {
            return cached;
        }
        League resolved = leagueReferenceGateway.resolveOrCreateLeague(externalId);
        cache.put(externalId, resolved);
        return resolved;
    }

    private RunIngestionCatchupResponseModel toResponseModel(CatchupResult result) {
        return new RunIngestionCatchupResponseModel(
                result.hoursProcessed(),
                result.fullyCaughtUp(),
                result.lastProcessedChangeId(),
                result.skippedCount());
    }

    private record CatchupResult(
            long lastProcessedChangeId, int hoursProcessed, int skippedCount, boolean fullyCaughtUp) {
    }

    private record SnapshotKey(long leagueId, long currencyAId, long currencyBId) {
        static SnapshotKey of(ExchangeMarketSnapshot snapshot) {
            return new SnapshotKey(
                    snapshot.league().id(), snapshot.currencyA().id(), snapshot.currencyB().id());
        }
    }

    private record UnresolvedPairKey(String leagueExternalId, String currencyAExternalId, String currencyBExternalId) {
        static UnresolvedPairKey of(ExchangeMarketEntry entry) {
            return new UnresolvedPairKey(
                    entry.leagueExternalId(), entry.currencyAExternalId(), entry.currencyBExternalId());
        }
    }
}
