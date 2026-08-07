package com.poeflipfinder.backend.framework.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** JPA mapping for the `league` table (docs/SCHEMA.md § League cache). */
@Entity
@Table(name = "league")
public class LeagueJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "external_id", nullable = false, unique = true)
    private String externalId;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "is_current", nullable = false)
    private boolean isCurrent;

    @Column(name = "has_exchange_activity", nullable = false)
    private boolean hasExchangeActivity;

    // True only for leagues an actual GGG Leagues API sync has confirmed
    // exist -- see V2__add_league_known_to_ggg_flag.sql. Ingestion creates
    // rows for any league string in raw trade data, including private
    // leagues GGG's public API never lists; this flag is what GET /leagues
    // filters on so those never leak into the dropdown.
    @Column(name = "known_to_ggg", nullable = false)
    private boolean knownToGgg;

    protected LeagueJpaEntity() {
        // JPA
    }

    public LeagueJpaEntity(String externalId, String displayName, boolean isCurrent, boolean hasExchangeActivity) {
        this.externalId = externalId;
        this.displayName = displayName;
        this.isCurrent = isCurrent;
        this.hasExchangeActivity = hasExchangeActivity;
    }

    public Long getId() {
        return id;
    }

    public String getExternalId() {
        return externalId;
    }

    public String getDisplayName() {
        return displayName;
    }

    public boolean isCurrent() {
        return isCurrent;
    }

    public boolean hasExchangeActivity() {
        return hasExchangeActivity;
    }

    public boolean isKnownToGgg() {
        return knownToGgg;
    }

    public void setHasExchangeActivity(boolean hasExchangeActivity) {
        this.hasExchangeActivity = hasExchangeActivity;
    }

    public void setKnownToGgg(boolean knownToGgg) {
        this.knownToGgg = knownToGgg;
    }

    public void setDisplayName(String displayName) {
        this.displayName = displayName;
    }

    public void setCurrent(boolean current) {
        isCurrent = current;
    }
}
