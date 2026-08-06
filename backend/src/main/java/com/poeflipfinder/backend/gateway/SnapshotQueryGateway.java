package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.ExchangeMarketSnapshot;
import java.util.List;

/**
 * Read side of the generation-tag hot-swap (docs/SCHEMA.md § Ingestion state
 * and market data) -- deliberately separate from SnapshotRepositoryGateway,
 * which is write-only and owned by the ingestion use case (Interface
 * Segregation: different callers, different lifecycles).
 */
public interface SnapshotQueryGateway {

    /**
     * All snapshots in the currently-active generation for one league. Empty
     * if the league is unrecognized or no generation has ever gone live yet.
     */
    List<ExchangeMarketSnapshot> findActiveSnapshots(String leagueExternalId);
}
