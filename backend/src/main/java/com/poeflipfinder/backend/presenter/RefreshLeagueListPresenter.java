package com.poeflipfinder.backend.presenter;

import com.poeflipfinder.backend.usecase.refreshleaguelist.RefreshLeagueListOutputBoundary;
import com.poeflipfinder.backend.usecase.refreshleaguelist.RefreshLeagueListResponseModel;
import java.util.List;

/** Same ViewModel shape as ResolveLeagueListPresenter -- both produce the Feature D dropdown's rows. */
public class RefreshLeagueListPresenter implements RefreshLeagueListOutputBoundary {

    private List<LeagueViewModel> viewModel = List.of();

    @Override
    public void present(RefreshLeagueListResponseModel response) {
        viewModel = response.leagues().stream()
                .map(league -> new LeagueViewModel(league.externalId(), league.displayName(), league.isCurrent()))
                .toList();
    }

    public List<LeagueViewModel> viewModel() {
        return viewModel;
    }
}
