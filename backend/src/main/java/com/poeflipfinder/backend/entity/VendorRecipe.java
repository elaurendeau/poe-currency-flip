package com.poeflipfinder.backend.entity;

/**
 * A vendor sell-rate or multi-item recipe, manually captured from the PoE Wiki
 * per docs/DATA_SOURCES.md. A plain sell rate is just inputQuantity = 1.
 */
public record VendorRecipe(
        Long id,
        Currency inputCurrency,
        int inputQuantity,
        Currency outputCurrency,
        int outputQuantity) {
}
