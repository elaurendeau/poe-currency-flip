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
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Exercises the generation-tag hot-swap against H2 rather than the real
 * Postgres migration -- V1__init_schema.sql's SQL isn't portable to H2 as-is.
 * Production schema correctness is separately covered by
 * spring.jpa.hibernate.ddl-auto=validate plus the docker-compose/real-Postgres
 * manual verification described in this feature's implementation plan.
 */
@DataJpaTest
@TestPropertySource(properties = {"spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=create-drop"})
@Import(JpaSnapshotRepositoryGatewayTest.GatewayTestConfig.class)
class JpaSnapshotRepositoryGatewayTest {

    // Registered as a real Spring bean (as GatewayConfig does in
    // production) rather than plain `new` -- @Transactional only takes
    // effect via Spring's AOP proxy around a container-managed bean.
    // A manually-`new`'d instance silently no-ops the annotation, which is
    // exactly how the missing @Transactional on discardGeneration slipped
    // past this test class originally: the ambient test-managed
    // transaction masked it either way.
    @TestConfiguration
    static class GatewayTestConfig {
        @Bean
        Clock clock() {
            return Clock.fixed(Instant.parse("2026-08-06T12:00:00Z"), ZoneOffset.UTC);
        }

        @Bean
        JpaSnapshotRepositoryGateway jpaSnapshotRepositoryGateway(
                ExchangeIngestionStateJpaRepository ingestionStateJpaRepository,
                ExchangeMarketSnapshotJpaRepository snapshotJpaRepository,
                Clock clock) {
            return new JpaSnapshotRepositoryGateway(ingestionStateJpaRepository, snapshotJpaRepository, clock);
        }
    }

    @Autowired
    private ExchangeIngestionStateJpaRepository ingestionStateJpaRepository;

    @Autowired
    private ExchangeMarketSnapshotJpaRepository snapshotJpaRepository;

    @Autowired
    private LeagueJpaRepository leagueJpaRepository;

    @Autowired
    private CurrencyJpaRepository currencyJpaRepository;

    @Autowired
    private JpaSnapshotRepositoryGateway gateway;

    @Autowired
    private Clock clock;

    private League league;
    private Currency currencyA;
    private Currency currencyB;

    @BeforeEach
    void seedSingletonRowAndReferenceData() {
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 0L, clock.instant()));

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

    @AfterEach
    void cleanUpAnyNonRolledBackState() {
        // The NOT_SUPPORTED regression test below runs outside the
        // ambient test transaction Spring would otherwise roll back --
        // its inserts commit for real, so they're cleaned up explicitly
        // rather than leaking into later tests. A no-op for every other
        // (transactional) test, since their rows are rolled back already.
        snapshotJpaRepository.deleteAll();
        ingestionStateJpaRepository.deleteAll();
        leagueJpaRepository.deleteAll();
        currencyJpaRepository.deleteAll();
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

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void discardGeneration_worksOutsideAnyAmbientTransaction_regressionForMissingTransactionalAnnotation() {
        // Regression test: discardGeneration issues a bulk @Modifying
        // delete query, which JPA requires an active transaction to run.
        // @DataJpaTest wraps every test method in its own transaction by
        // default, which silently masked a missing @Transactional on the
        // gateway method itself -- it worked in tests but threw
        // jakarta.persistence.TransactionRequiredException in production.
        // Suspending the test's ambient transaction here reproduces that.
        long generationId = 500L;
        gateway.saveSnapshots(List.of(oneSnapshot(generationId)));

        gateway.discardGeneration(generationId);

        assertThat(snapshotJpaRepository.findAll()).isEmpty();
    }

    private ExchangeMarketSnapshot oneSnapshot(long generationId) {
        return new ExchangeMarketSnapshot(
                null, generationId, league, currencyA, currencyB, clock.instant(), 1, 2, 3, 4, 5, 6, 1.0, 2.0, 3.0, 4.0);
    }
}
