package com.poeflipfinder.backend.framework.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.IngestionFreshness;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

/**
 * Exercises the generation-tag hot-swap against H2 rather than the real
 * Postgres migration -- V1__init_schema.sql's SQL isn't portable to H2 as-is.
 * Production schema correctness is separately covered by
 * spring.jpa.hibernate.ddl-auto=validate plus the docker-compose/real-Postgres
 * manual verification described in this feature's implementation plan.
 */
@DataJpaTest
@TestPropertySource(properties = {"spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=create-drop"})
class JpaSnapshotRepositoryGatewayTest {

    @Autowired
    private ExchangeIngestionStateJpaRepository ingestionStateJpaRepository;

    @Autowired
    private ExchangeMarketSnapshotJpaRepository snapshotJpaRepository;

    @Autowired
    private LeagueJpaRepository leagueJpaRepository;

    @Autowired
    private CurrencyJpaRepository currencyJpaRepository;

    private final Clock clock = Clock.fixed(Instant.parse("2026-08-06T12:00:00Z"), ZoneOffset.UTC);
    private JpaSnapshotRepositoryGateway gateway;
    private League league;
    private Currency currencyA;
    private Currency currencyB;

    @BeforeEach
    void seedSingletonRowAndReferenceData() {
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 0L, clock.instant()));
        gateway = new JpaSnapshotRepositoryGateway(ingestionStateJpaRepository, snapshotJpaRepository, clock);

        LeagueJpaEntity leagueJpaEntity =
                leagueJpaRepository.save(new LeagueJpaEntity("Standard", "Standard", false, true));
        CurrencyJpaEntity currencyAJpaEntity = currencyJpaRepository.save(
                new CurrencyJpaEntity("Metadata/Items/Currency/A", "Currency A", null, Currency.ItemType.CURRENCY));
        CurrencyJpaEntity currencyBJpaEntity = currencyJpaRepository.save(
                new CurrencyJpaEntity("Metadata/Items/Currency/B", "Currency B", null, Currency.ItemType.CURRENCY));

        league = new League(
                leagueJpaEntity.getId(), leagueJpaEntity.getExternalId(), leagueJpaEntity.getDisplayName(), false, true);
        currencyA = new Currency(
                currencyAJpaEntity.getId(), currencyAJpaEntity.getExternalId(), "Currency A", null, Currency.ItemType.CURRENCY);
        currencyB = new Currency(
                currencyBJpaEntity.getId(), currencyBJpaEntity.getExternalId(), "Currency B", null, Currency.ItemType.CURRENCY);
    }

    @Test
    void readIngestionState_returnsNullFields_beforeAnyRefreshHasEverCommitted() {
        IngestionFreshness freshness = gateway.readIngestionState();

        assertThat(freshness.lastProcessedChangeId()).isNull();
        assertThat(freshness.activeGenerationRefreshedAt()).isNull();
    }

    @Test
    void commitGeneration_advancesCheckpoint_andPurgesTheSupersededGeneration() {
        long firstGenerationId = 100L;
        gateway.saveSnapshots(List.of(oneSnapshot(firstGenerationId)));
        gateway.commitGeneration(firstGenerationId, 1_000_000L);

        assertThat(snapshotJpaRepository.findAll()).hasSize(1);
        IngestionFreshness afterFirst = gateway.readIngestionState();
        assertThat(afterFirst.lastProcessedChangeId()).isEqualTo(1_000_000L);
        assertThat(afterFirst.activeGenerationRefreshedAt()).isEqualTo(clock.instant());

        long secondGenerationId = 200L;
        gateway.saveSnapshots(List.of(oneSnapshot(secondGenerationId)));
        gateway.commitGeneration(secondGenerationId, 2_000_000L);

        List<ExchangeMarketSnapshotJpaEntity> remaining = snapshotJpaRepository.findAll();
        assertThat(remaining).hasSize(1);
        assertThat(remaining.get(0).getGenerationId()).isEqualTo(secondGenerationId);
    }

    @Test
    void discardGeneration_deletesItsRows_withoutTouchingTheCheckpoint() {
        long generationId = 300L;
        gateway.saveSnapshots(List.of(oneSnapshot(generationId)));

        gateway.discardGeneration(generationId);

        assertThat(snapshotJpaRepository.findAll()).isEmpty();
        assertThat(gateway.readIngestionState().lastProcessedChangeId()).isNull();
    }

    private ExchangeMarketSnapshot oneSnapshot(long generationId) {
        return new ExchangeMarketSnapshot(
                null, generationId, league, currencyA, currencyB, clock.instant(), 1, 2, 3, 4, 5, 6, 1.0, 2.0, 3.0, 4.0);
    }
}
