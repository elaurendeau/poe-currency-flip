package com.poeflipfinder.backend.usecase.runingestioncatchup;

import java.time.Duration;

/**
 * The two tuning knobs for one bounded catch-up walk (docs/ARCHITECTURE.md §
 * Currency Exchange Ingestion), bundled since they're always supplied
 * together from application.yml.
 */
public record CatchupCapPolicy(int maxHoursPerCall, Duration firstRunLookback) {
}
