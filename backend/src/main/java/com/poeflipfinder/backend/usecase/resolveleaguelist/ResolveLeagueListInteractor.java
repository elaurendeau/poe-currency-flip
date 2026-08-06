package com.poeflipfinder.backend.usecase.resolveleaguelist;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueGateway;
import java.util.List;

/**
 * Orchestrates league resolution (docs/ARCHITECTURE.md § League Resolution).
 * Steps 1-2 (fetch, SSF filtering) happen in the gateway; step 4 (default
 * selection) happens here since it's application policy, not raw-data
 * normalization. Step 3 (cross-check against ingested Currency Exchange
 * activity) is not yet wired in -- it depends on the ingestion service
 * (a later task) and will be added as a second gateway call here once that
 * exists, without changing this class's public shape.
 */
public class ResolveLeagueListInteractor implements ResolveLeagueListInputBoundary {

    private final LeagueGateway leagueGateway;
    private final ResolveLeagueListOutputBoundary outputBoundary;

    public ResolveLeagueListInteractor(
            LeagueGateway leagueGateway, ResolveLeagueListOutputBoundary outputBoundary) {
        this.leagueGateway = leagueGateway;
        this.outputBoundary = outputBoundary;
    }

    @Override
    public void resolveLeagueList() {
        List<League> leagues = leagueGateway.fetchLeagues();
        outputBoundary.present(new ResolveLeagueListResponseModel(leagues));
    }
}
