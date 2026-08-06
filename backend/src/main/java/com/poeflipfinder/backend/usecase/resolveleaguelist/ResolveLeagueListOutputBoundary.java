package com.poeflipfinder.backend.usecase.resolveleaguelist;

/** What the interactor calls with its result; a Presenter implements this. */
public interface ResolveLeagueListOutputBoundary {

    void present(ResolveLeagueListResponseModel response);
}
