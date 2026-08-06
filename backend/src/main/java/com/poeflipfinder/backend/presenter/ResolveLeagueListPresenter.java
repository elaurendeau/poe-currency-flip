package com.poeflipfinder.backend.presenter;

import com.poeflipfinder.backend.usecase.resolveleaguelist.ResolveLeagueListOutputBoundary;
import com.poeflipfinder.backend.usecase.resolveleaguelist.ResolveLeagueListResponseModel;
import java.util.List;

/**
 * Shapes the interactor's result into a ViewModel. Formatting/shaping
 * decisions live here, not in the interactor (docs/CODE_STYLE.md § Clean
 * Architecture).
 */
public class ResolveLeagueListPresenter implements ResolveLeagueListOutputBoundary {

    private List<LeagueViewModel> viewModel = List.of();

    @Override
    public void present(ResolveLeagueListResponseModel response) {
        viewModel = response.leagues().stream()
                .map(league -> new LeagueViewModel(league.externalId(), league.displayName(), league.isCurrent()))
                .toList();
    }

    public List<LeagueViewModel> viewModel() {
        return viewModel;
    }
}
