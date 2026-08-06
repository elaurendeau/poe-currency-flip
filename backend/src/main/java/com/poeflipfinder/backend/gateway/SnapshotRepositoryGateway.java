package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import java.util.List;

/**
 * Defined by the use-case ring: the generation-tag hot-swap mechanics for
 * exchange_ingestion_state / exchange_market_snapshot (docs/SCHEMA.md §
 * Ingestion state and market data). Takes already-resolved entities in --
 * currency/league resolution is CurrencyReferenceGateway's and
 * LeagueReferenceGateway's job, not this seam's.
 */
public interface SnapshotRepositoryGateway {

    IngestionFreshness readIngestionState();

    /** Mints a new generation tag for this ingestion run's rows. */
    long startNewGeneration();

    void saveSnapshots(List<ExchangeMarketSnapshot> snapshots);

    /**
     * Atomically advances the checkpoint, flips the active generation, and
     * purges the superseded generation's rows -- docs/SCHEMA.md's "Refresh
     * flow" step 3, in one place. Called whether the walk reached the true
     * tip or just hit its per-call hour cap -- both are a normal, successful
     * stop (docs/ARCHITECTURE.md § Currency Exchange Ingestion).
     */
    void commitGeneration(long generationId, long newLastProcessedChangeId);

    /** Discards a generation's rows without touching the active checkpoint -- a hard failure mid-walk. */
    void discardGeneration(long generationId);
}
