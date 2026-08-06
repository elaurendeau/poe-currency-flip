package com.poeflipfinder.backend.framework.persistence;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ExchangeMarketSnapshotJpaRepository extends JpaRepository<ExchangeMarketSnapshotJpaEntity, Long> {

    @Modifying
    @Query("delete from ExchangeMarketSnapshotJpaEntity e where e.generationId = :generationId")
    void deleteByGenerationId(@Param("generationId") long generationId);

    List<ExchangeMarketSnapshotJpaEntity> findByGenerationIdAndLeagueId(long generationId, long leagueId);
}
