package com.poeflipfinder.backend.framework.persistence;

import com.poeflipfinder.backend.entity.Currency;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** JPA mapping for the `currency` table (docs/SCHEMA.md § Reference data). */
@Entity
@Table(name = "currency")
public class CurrencyJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "external_id", nullable = false, unique = true)
    private String externalId;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "icon_url")
    private String iconUrl;

    @Enumerated(EnumType.STRING)
    @Column(name = "item_type", nullable = false)
    private Currency.ItemType itemType;

    protected CurrencyJpaEntity() {
        // JPA
    }

    public CurrencyJpaEntity(String externalId, String displayName, String iconUrl, Currency.ItemType itemType) {
        this.externalId = externalId;
        this.displayName = displayName;
        this.iconUrl = iconUrl;
        this.itemType = itemType;
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

    public String getIconUrl() {
        return iconUrl;
    }

    public Currency.ItemType getItemType() {
        return itemType;
    }
}
