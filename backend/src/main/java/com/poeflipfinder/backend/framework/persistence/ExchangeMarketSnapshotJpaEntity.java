package com.poeflipfinder.backend.framework.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

/**
 * JPA mapping for the `exchange_market_snapshot` table (docs/SCHEMA.md §
 * Ingestion state and market data). Plain FK long columns rather than
 * @ManyToOne relations -- ids are already resolved by persistence time, and
 * this avoids cascade/N+1 concerns on what is meant to be a fast bulk-insert
 * path.
 */
@Entity
@Table(name = "exchange_market_snapshot")
public class ExchangeMarketSnapshotJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "generation_id", nullable = false)
    private long generationId;

    @Column(name = "league_id", nullable = false)
    private long leagueId;

    @Column(name = "currency_a_id", nullable = false)
    private long currencyAId;

    @Column(name = "currency_b_id", nullable = false)
    private long currencyBId;

    @Column(name = "snapshot_hour", nullable = false)
    private Instant snapshotHour;

    @Column(name = "volume_traded_a", nullable = false)
    private long volumeTradedA;

    @Column(name = "volume_traded_b", nullable = false)
    private long volumeTradedB;

    @Column(name = "lowest_stock_a", nullable = false)
    private long lowestStockA;

    @Column(name = "highest_stock_a", nullable = false)
    private long highestStockA;

    @Column(name = "lowest_stock_b", nullable = false)
    private long lowestStockB;

    @Column(name = "highest_stock_b", nullable = false)
    private long highestStockB;

    @Column(name = "lowest_ratio_a", nullable = false)
    private double lowestRatioA;

    @Column(name = "highest_ratio_a", nullable = false)
    private double highestRatioA;

    @Column(name = "lowest_ratio_b", nullable = false)
    private double lowestRatioB;

    @Column(name = "highest_ratio_b", nullable = false)
    private double highestRatioB;

    protected ExchangeMarketSnapshotJpaEntity() {
        // JPA
    }

    public ExchangeMarketSnapshotJpaEntity(
            long generationId,
            long leagueId,
            long currencyAId,
            long currencyBId,
            Instant snapshotHour,
            long volumeTradedA,
            long volumeTradedB,
            long lowestStockA,
            long highestStockA,
            long lowestStockB,
            long highestStockB,
            double lowestRatioA,
            double highestRatioA,
            double lowestRatioB,
            double highestRatioB) {
        this.generationId = generationId;
        this.leagueId = leagueId;
        this.currencyAId = currencyAId;
        this.currencyBId = currencyBId;
        this.snapshotHour = snapshotHour;
        this.volumeTradedA = volumeTradedA;
        this.volumeTradedB = volumeTradedB;
        this.lowestStockA = lowestStockA;
        this.highestStockA = highestStockA;
        this.lowestStockB = lowestStockB;
        this.highestStockB = highestStockB;
        this.lowestRatioA = lowestRatioA;
        this.highestRatioA = highestRatioA;
        this.lowestRatioB = lowestRatioB;
        this.highestRatioB = highestRatioB;
    }

    public Long getId() {
        return id;
    }

    public long getGenerationId() {
        return generationId;
    }

    public long getLeagueId() {
        return leagueId;
    }

    public long getCurrencyAId() {
        return currencyAId;
    }

    public long getCurrencyBId() {
        return currencyBId;
    }

    public Instant getSnapshotHour() {
        return snapshotHour;
    }

    public long getVolumeTradedA() {
        return volumeTradedA;
    }

    public long getVolumeTradedB() {
        return volumeTradedB;
    }

    public long getLowestStockA() {
        return lowestStockA;
    }

    public long getHighestStockA() {
        return highestStockA;
    }

    public long getLowestStockB() {
        return lowestStockB;
    }

    public long getHighestStockB() {
        return highestStockB;
    }

    public double getLowestRatioA() {
        return lowestRatioA;
    }

    public double getHighestRatioA() {
        return highestRatioA;
    }

    public double getLowestRatioB() {
        return lowestRatioB;
    }

    public double getHighestRatioB() {
        return highestRatioB;
    }
}
