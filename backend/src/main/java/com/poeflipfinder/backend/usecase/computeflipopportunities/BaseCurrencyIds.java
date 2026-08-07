package com.poeflipfinder.backend.usecase.computeflipopportunities;

/**
 * GGG's own path-style item identifiers for the two currencies every
 * Exchange Spread and Bulk Buy opportunity is anchored on -- see
 * docs/DATA_SOURCES.md § Item Icons for where this externalId format comes
 * from.
 */
final class BaseCurrencyIds {

    static final String CHAOS_EXTERNAL_ID = "Metadata/Items/Currency/CurrencyRerollRare";
    static final String DIVINE_EXTERNAL_ID = "Metadata/Items/Currency/CurrencyModValues";

    private BaseCurrencyIds() {}
}
