package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.gateway.IngestionFreshness;
import com.poeflipfinder.backend.gateway.SnapshotRepositoryGateway;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import org.springframework.transaction.annotation.Transactional;

/**
 * The Frameworks & Drivers implementation of SnapshotRepositoryGateway.
 * commitGeneration is the single short transaction docs/SCHEMA.md's "Refresh
 * flow" step 3 describes -- the only moment new data becomes visible.
 */
public class JpaSnapshotRepositoryGateway implements SnapshotRepositoryGateway {

    private static final short INGESTION_STATE_ID = 1;

    // V1__init_schema.sql seeds active_generation_id=0 as the "no
    // generation has ever gone live yet" sentinel -- skip the purge then,
    // since there's nothing to delete.
    private static final long NO_GENERATION_YET = 0;

    private final ExchangeIngestionStateJpaRepository ingestionStateJpaRepository;
    private final ExchangeMarketSnapshotJpaRepository snapshotJpaRepository;
    private final Clock clock;

    public JpaSnapshotRepositoryGateway(
            ExchangeIngestionStateJpaRepository ingestionStateJpaRepository,
            ExchangeMarketSnapshotJpaRepository snapshotJpaRepository,
            Clock clock) {
        this.ingestionStateJpaRepository = ingestionStateJpaRepository;
        this.snapshotJpaRepository = snapshotJpaRepository;
        this.clock = clock;
    }

    @Override
    public IngestionFreshness readIngestionState() {
        ExchangeIngestionStateJpaEntity state = findIngestionState();
        return new IngestionFreshness(state.getLastProcessedChangeId(), state.getActiveGenerationRefreshedAt());
    }

    @Override
    public long startNewGeneration() {
        return clock.millis();
    }

    @Override
    public void saveSnapshots(List<ExchangeMarketSnapshot> snapshots) {
        List<ExchangeMarketSnapshotJpaEntity> jpaEntities = snapshots.stream().map(this::toJpaEntity).toList();
        snapshotJpaRepository.saveAll(jpaEntities);
    }

    @Override
    @Transactional
    public void commitGeneration(long generationId, long newLastProcessedChangeId) {
        ExchangeIngestionStateJpaEntity state = findIngestionState();
        long supersededGenerationId = state.getActiveGenerationId();

        state.setActiveGenerationId(generationId);
        state.setLastProcessedChangeId(newLastProcessedChangeId);
        state.setActiveGenerationRefreshedAt(Instant.now(clock));
        state.setUpdatedAt(Instant.now(clock));
        ingestionStateJpaRepository.save(state);

        if (supersededGenerationId != NO_GENERATION_YET) {
            snapshotJpaRepository.deleteByGenerationId(supersededGenerationId);
        }
    }

    @Override
    public void discardGeneration(long generationId) {
        snapshotJpaRepository.deleteByGenerationId(generationId);
    }

    private ExchangeIngestionStateJpaEntity findIngestionState() {
        return ingestionStateJpaRepository
                .findById(INGESTION_STATE_ID)
                .orElseThrow(() -> new IllegalStateException(
                        "exchange_ingestion_state singleton row is missing -- V1__init_schema.sql should have seeded it"));
    }

    private ExchangeMarketSnapshotJpaEntity toJpaEntity(ExchangeMarketSnapshot snapshot) {
        return new ExchangeMarketSnapshotJpaEntity(
                snapshot.generationId(),
                snapshot.league().id(),
                snapshot.currencyA().id(),
                snapshot.currencyB().id(),
                snapshot.snapshotHour(),
                snapshot.volumeTradedA(),
                snapshot.volumeTradedB(),
                snapshot.lowestStockA(),
                snapshot.highestStockA(),
                snapshot.lowestStockB(),
                snapshot.highestStockB(),
                snapshot.lowestRatioA(),
                snapshot.highestRatioA(),
                snapshot.lowestRatioB(),
                snapshot.highestRatioB());
    }
}
