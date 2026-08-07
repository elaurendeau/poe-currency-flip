package com.poeflipfinder.backend.usecase.resolveleaguelist;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueQueryGateway;
import java.util.List;

/**
 * Orchestrates the league list read (docs/ARCHITECTURE.md § League
 * Resolution). This is a DB-cached read, not a live GGG call -- every page
 * load hitting GGG directly made the league dropdown feel perpetually
 * loading. The live fetch + cache population happens in
 * usecase.refreshleaguelist.RefreshLeagueListInteractor instead, triggered
 * only by the user's explicit "Refresh leagues" action (docs/PRD.md § 7.7).
 */
public class ResolveLeagueListInteractor implements ResolveLeagueListInputBoundary {

    private final LeagueQueryGateway leagueQueryGateway;
    private final ResolveLeagueListOutputBoundary outputBoundary;

    public ResolveLeagueListInteractor(
            LeagueQueryGateway leagueQueryGateway, ResolveLeagueListOutputBoundary outputBoundary) {
        this.leagueQueryGateway = leagueQueryGateway;
        this.outputBoundary = outputBoundary;
    }

    @Override
    public void resolveLeagueList() {
        List<League> leagues = leagueQueryGateway.findAllLeagues();
        outputBoundary.present(new ResolveLeagueListResponseModel(leagues));
    }
}
