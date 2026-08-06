package com.poeflipfinder.backend.entity;

/** A quantity of a specific currency, e.g. "86 Orb of Transmutation." */
public record CurrencyAmount(Currency currency, double quantity) {
}
