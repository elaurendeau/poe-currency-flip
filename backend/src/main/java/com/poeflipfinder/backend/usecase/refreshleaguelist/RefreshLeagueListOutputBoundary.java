package com.poeflipfinder.backend.usecase.refreshleaguelist;

/** What the interactor calls with its result; a Presenter implements this. */
public interface RefreshLeagueListOutputBoundary {

    void present(RefreshLeagueListResponseModel response);
}
