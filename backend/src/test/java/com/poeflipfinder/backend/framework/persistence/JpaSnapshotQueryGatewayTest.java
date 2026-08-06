package com.poeflipfinder.backend.framework.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

/**
 * Exercises the read side of the generation-tag hot-swap against H2, mirroring
 * JpaSnapshotRepositoryGatewayTest's approach -- V1__init_schema.sql's SQL
 * isn't portable to H2 as-is.
 */
@DataJpaTest
@TestPropertySource(properties = {"spring.flyway.enabled=false", "spring.jpa.hibernate.ddl-auto=create-drop"})
class JpaSnapshotQueryGatewayTest {

    private static final Instant NOW = Instant.parse("2026-08-06T12:00:00Z");
    private static final Clock CLOCK = Clock.fixed(NOW, ZoneOffset.UTC);

    @Autowired
    private ExchangeIngestionStateJpaRepository ingestionStateJpaRepository;

    @Autowired
    private ExchangeMarketSnapshotJpaRepository snapshotJpaRepository;

    @Autowired
    private LeagueJpaRepository leagueJpaRepository;

    @Autowired
    private CurrencyJpaRepository currencyJpaRepository;

    private JpaSnapshotQueryGateway gateway;
    private long standardLeagueId;
    private long hardcoreLeagueId;
    private long currencyAId;
    private long currencyBId;

    @BeforeEach
    void seedReferenceData() {
        gateway = new JpaSnapshotQueryGateway(
                leagueJpaRepository, currencyJpaRepository, snapshotJpaRepository, ingestionStateJpaRepository);

        standardLeagueId =
                leagueJpaRepository.save(new LeagueJpaEntity("Standard", "Standard", false, true)).getId();
        hardcoreLeagueId =
                leagueJpaRepository.save(new LeagueJpaEntity("Hardcore", "Hardcore", false, true)).getId();
        currencyAId = currencyJpaRepository
                .save(new CurrencyJpaEntity("Metadata/Items/Currency/A", "Currency A", null, Currency.ItemType.CURRENCY))
                .getId();
        currencyBId = currencyJpaRepository
                .save(new CurrencyJpaEntity("Metadata/Items/Currency/B", "Currency B", null, Currency.ItemType.CURRENCY))
                .getId();
    }

    @AfterEach
    void cleanUp() {
        snapshotJpaRepository.deleteAll();
        ingestionStateJpaRepository.deleteAll();
        leagueJpaRepository.deleteAll();
        currencyJpaRepository.deleteAll();
    }

    @Test
    void findActiveSnapshots_returnsOnlyActiveGenerationRowsForThatLeague() {
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 999L, NOW));
        snapshotJpaRepository.save(oneSnapshot(999L, standardLeagueId));
        snapshotJpaRepository.save(oneSnapshot(111L, standardLeagueId)); // stale, superseded generation

        List<ExchangeMarketSnapshot> result = gateway.findActiveSnapshots("Standard");

        assertThat(result).hasSize(1);
        ExchangeMarketSnapshot snapshot = result.get(0);
        assertThat(snapshot.generationId()).isEqualTo(999L);
        assertThat(snapshot.league().externalId()).isEqualTo("Standard");
        assertThat(snapshot.currencyA().externalId()).isEqualTo("Metadata/Items/Currency/A");
        assertThat(snapshot.currencyB().externalId()).isEqualTo("Metadata/Items/Currency/B");
        assertThat(snapshot.lowestRatioA()).isEqualTo(1.0);
        assertThat(snapshot.highestRatioB()).isEqualTo(4.0);
    }

    @Test
    void findActiveSnapshots_scopesToTheRequestedLeagueOnly() {
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 999L, NOW));
        snapshotJpaRepository.save(oneSnapshot(999L, standardLeagueId));
        snapshotJpaRepository.save(oneSnapshot(999L, hardcoreLeagueId));

        List<ExchangeMarketSnapshot> result = gateway.findActiveSnapshots("Standard");

        assertThat(result).extracting(s -> s.league().externalId()).containsExactly("Standard");
    }

    @Test
    void findActiveSnapshots_multipleRows_allHydratedWithFullCurrencyAndLeagueObjects() {
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 999L, NOW));
        long currencyCId = currencyJpaRepository
                .save(new CurrencyJpaEntity("Metadata/Items/Currency/C", "Currency C", null, Currency.ItemType.CURRENCY))
                .getId();
        snapshotJpaRepository.save(oneSnapshot(999L, standardLeagueId));
        snapshotJpaRepository.save(new ExchangeMarketSnapshotJpaEntity(
                999L, standardLeagueId, currencyAId, currencyCId, NOW, 1, 2, 3, 4, 5, 6, 1.0, 2.0, 3.0, 4.0));

        List<ExchangeMarketSnapshot> result = gateway.findActiveSnapshots("Standard");

        assertThat(result)
                .extracting(s -> s.currencyA().displayName(), s -> s.currencyB().displayName())
                .containsExactlyInAnyOrder(tuple("Currency A", "Currency B"), tuple("Currency A", "Currency C"));
    }

    @Test
    void findActiveSnapshots_unknownLeague_returnsEmptyList() {
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 999L, NOW));
        snapshotJpaRepository.save(oneSnapshot(999L, standardLeagueId));

        assertThat(gateway.findActiveSnapshots("NotARealLeague")).isEmpty();
    }

    @Test
    void findActiveSnapshots_noGenerationEverCommitted_returnsEmptyList() {
        // active_generation_id=0 sentinel -- V1__init_schema.sql's "nothing
        // has ever gone live yet" state.
        ingestionStateJpaRepository.save(new ExchangeIngestionStateJpaEntity((short) 1, 0L, NOW));
        snapshotJpaRepository.save(oneSnapshot(0L, standardLeagueId));

        assertThat(gateway.findActiveSnapshots("Standard")).isEmpty();
    }

    private ExchangeMarketSnapshotJpaEntity oneSnapshot(long generationId, long leagueId) {
        return new ExchangeMarketSnapshotJpaEntity(
                generationId, leagueId, currencyAId, currencyBId, NOW, 1, 2, 3, 4, 5, 6, 1.0, 2.0, 3.0, 4.0);
    }
}
