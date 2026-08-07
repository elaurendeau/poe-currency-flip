package com.poeflipfinder.backend.usecase.refreshleaguelist;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueGateway;
import com.poeflipfinder.backend.gateway.LeagueSyncGateway;
import java.util.List;

/**
 * The only place that ever calls out to GGG's live Leagues API -- triggered
 * exclusively by the user's explicit "Refresh leagues" action
 * (docs/PRD.md § 7.7), never on a normal page load. Syncs the fetched
 * leagues into the cache so subsequent reads (ResolveLeagueListInteractor)
 * stay fast and don't depend on GGG being reachable.
 */
public class RefreshLeagueListInteractor implements RefreshLeagueListInputBoundary {

    private final LeagueGateway leagueGateway;
    private final LeagueSyncGateway leagueSyncGateway;
    private final RefreshLeagueListOutputBoundary outputBoundary;

    public RefreshLeagueListInteractor(
            LeagueGateway leagueGateway,
            LeagueSyncGateway leagueSyncGateway,
            RefreshLeagueListOutputBoundary outputBoundary) {
        this.leagueGateway = leagueGateway;
        this.leagueSyncGateway = leagueSyncGateway;
        this.outputBoundary = outputBoundary;
    }

    @Override
    public void refreshLeagueList() {
        List<League> fetched = leagueGateway.fetchLeagues();
        List<League> synced = leagueSyncGateway.upsertFromGgg(fetched);
        outputBoundary.present(new RefreshLeagueListResponseModel(synced));
    }
}
