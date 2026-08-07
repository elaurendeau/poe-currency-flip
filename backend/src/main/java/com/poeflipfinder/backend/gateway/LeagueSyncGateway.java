package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.League;
import java.util.List;

/**
 * Write side of the league cache, populated from a live GGG Leagues API
 * fetch (docs/PRD.md § 7.7 manual refresh). Deliberately separate from
 * LeagueReferenceGateway, which resolves/creates a league from the Currency
 * Exchange ingestion payload instead -- different caller, different data
 * available at that seam (only an id string, no display name or current-league
 * flag). This gateway updates displayName/isCurrent from the richer GGG
 * payload while preserving whatever hasExchangeActivity ingestion already
 * determined.
 */
public interface LeagueSyncGateway {

    List<League> upsertFromGgg(List<League> leagues);
}
