package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.Currency;

/**
 * The Chaos<->Divine exchange rate for a league's active generation,
 * averaged from the hour's two rate extremes -- a point-estimate "fair
 * value" for normalizing profit figures, not a proposed trade. Used to
 * convert Divine-denominated amounts into Chaos (Exchange Spread) and to
 * benchmark the direct rate a Bulk Buy opportunity must beat.
 */
record DivineChaosRate(Currency chaosCurrency, Currency divineCurrency, double chaosPerDivine) {}
