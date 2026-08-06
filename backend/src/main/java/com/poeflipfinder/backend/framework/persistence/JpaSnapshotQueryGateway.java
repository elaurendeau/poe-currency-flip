package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.SnapshotQueryGateway;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * The Frameworks & Drivers implementation of SnapshotQueryGateway. Plain FK
 * long columns on ExchangeMarketSnapshotJpaEntity (no @ManyToOne relations,
 * see that class's javadoc) mean hydrating back to domain objects needs
 * explicit batched currency lookups rather than a relation traversal.
 */
public class JpaSnapshotQueryGateway implements SnapshotQueryGateway {

    // Same sentinel JpaSnapshotRepositoryGateway's write side uses --
    // V1__init_schema.sql seeds active_generation_id=0 for "nothing has
    // ever gone live yet".
    private static final long NO_GENERATION_YET = 0;
    private static final short INGESTION_STATE_ID = 1;

    private final LeagueJpaRepository leagueJpaRepository;
    private final CurrencyJpaRepository currencyJpaRepository;
    private final ExchangeMarketSnapshotJpaRepository snapshotJpaRepository;
    private final ExchangeIngestionStateJpaRepository ingestionStateJpaRepository;

    public JpaSnapshotQueryGateway(
            LeagueJpaRepository leagueJpaRepository,
            CurrencyJpaRepository currencyJpaRepository,
            ExchangeMarketSnapshotJpaRepository snapshotJpaRepository,
            ExchangeIngestionStateJpaRepository ingestionStateJpaRepository) {
        this.leagueJpaRepository = leagueJpaRepository;
        this.currencyJpaRepository = currencyJpaRepository;
        this.snapshotJpaRepository = snapshotJpaRepository;
        this.ingestionStateJpaRepository = ingestionStateJpaRepository;
    }

    @Override
    public List<ExchangeMarketSnapshot> findActiveSnapshots(String leagueExternalId) {
        Optional<LeagueJpaEntity> leagueJpaEntity = leagueJpaRepository.findByExternalId(leagueExternalId);
        if (leagueJpaEntity.isEmpty()) {
            return List.of();
        }

        long activeGenerationId = ingestionStateJpaRepository
                .findById(INGESTION_STATE_ID)
                .map(ExchangeIngestionStateJpaEntity::getActiveGenerationId)
                .orElse(NO_GENERATION_YET);
        if (activeGenerationId == NO_GENERATION_YET) {
            return List.of();
        }

        List<ExchangeMarketSnapshotJpaEntity> rows = snapshotJpaRepository.findByGenerationIdAndLeagueId(
                activeGenerationId, leagueJpaEntity.get().getId());
        if (rows.isEmpty()) {
            return List.of();
        }

        Map<Long, CurrencyJpaEntity> currenciesById = hydrateCurrencies(rows);
        League league = toLeague(leagueJpaEntity.get());
        return rows.stream().map(row -> toEntity(row, league, currenciesById)).toList();
    }

    private Map<Long, CurrencyJpaEntity> hydrateCurrencies(List<ExchangeMarketSnapshotJpaEntity> rows) {
        Set<Long> currencyIds = Stream.concat(
                        rows.stream().map(ExchangeMarketSnapshotJpaEntity::getCurrencyAId),
                        rows.stream().map(ExchangeMarketSnapshotJpaEntity::getCurrencyBId))
                .collect(Collectors.toSet());
        return currencyJpaRepository.findAllById(currencyIds).stream()
                .collect(Collectors.toMap(CurrencyJpaEntity::getId, Function.identity()));
    }

    private ExchangeMarketSnapshot toEntity(
            ExchangeMarketSnapshotJpaEntity row, League league, Map<Long, CurrencyJpaEntity> currenciesById) {
        return new ExchangeMarketSnapshot(
                row.getId(),
                row.getGenerationId(),
                league,
                toCurrency(currenciesById.get(row.getCurrencyAId())),
                toCurrency(currenciesById.get(row.getCurrencyBId())),
                row.getSnapshotHour(),
                row.getVolumeTradedA(),
                row.getVolumeTradedB(),
                row.getLowestStockA(),
                row.getHighestStockA(),
                row.getLowestStockB(),
                row.getHighestStockB(),
                row.getLowestRatioA(),
                row.getHighestRatioA(),
                row.getLowestRatioB(),
                row.getHighestRatioB());
    }

    private League toLeague(LeagueJpaEntity jpaEntity) {
        return new League(
                jpaEntity.getId(),
                jpaEntity.getExternalId(),
                jpaEntity.getDisplayName(),
                jpaEntity.isCurrent(),
                jpaEntity.hasExchangeActivity());
    }

    private Currency toCurrency(CurrencyJpaEntity jpaEntity) {
        return new Currency(
                jpaEntity.getId(),
                jpaEntity.getExternalId(),
                jpaEntity.getDisplayName(),
                jpaEntity.getIconUrl(),
                jpaEntity.getItemType());
    }
}
