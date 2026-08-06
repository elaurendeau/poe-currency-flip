package com.poeflipfinder.backend.framework.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/**
 * JPA mapping for the singleton `exchange_ingestion_state` row (docs/SCHEMA.md
 * § Ingestion state and market data). V1__init_schema.sql seeds row id=1 with
 * active_generation_id=0 as the "no generation yet" sentinel -- this app
 * never inserts a new row, only updates the existing one.
 */
@Entity
@Table(name = "exchange_ingestion_state")
public class ExchangeIngestionStateJpaEntity {

    @Id
    private Short id;

    @Column(name = "last_processed_change_id")
    private Long lastProcessedChangeId;

    @Column(name = "active_generation_id", nullable = false)
    private long activeGenerationId;

    @Column(name = "active_generation_refreshed_at")
    private Instant activeGenerationRefreshedAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected ExchangeIngestionStateJpaEntity() {
        // JPA
    }

    /**
     * Production seeds the singleton row via V1__init_schema.sql's INSERT;
     * this constructor exists for test setups that bypass that migration
     * (e.g. an H2-backed slice using Hibernate-generated DDL).
     */
    public ExchangeIngestionStateJpaEntity(short id, long activeGenerationId, Instant updatedAt) {
        this.id = id;
        this.activeGenerationId = activeGenerationId;
        this.updatedAt = updatedAt;
    }

    public Short getId() {
        return id;
    }

    public Long getLastProcessedChangeId() {
        return lastProcessedChangeId;
    }

    public long getActiveGenerationId() {
        return activeGenerationId;
    }

    public Instant getActiveGenerationRefreshedAt() {
        return activeGenerationRefreshedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setLastProcessedChangeId(Long lastProcessedChangeId) {
        this.lastProcessedChangeId = lastProcessedChangeId;
    }

    public void setActiveGenerationId(long activeGenerationId) {
        this.activeGenerationId = activeGenerationId;
    }

    public void setActiveGenerationRefreshedAt(Instant activeGenerationRefreshedAt) {
        this.activeGenerationRefreshedAt = activeGenerationRefreshedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }
}
