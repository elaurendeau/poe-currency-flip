package com.poeflipfinder.backend.usecase.refreshleaguelist;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.poeflipfinder.backend.entity.League;
import com.poeflipfinder.backend.gateway.LeagueGateway;
import com.poeflipfinder.backend.gateway.LeagueSyncGateway;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class RefreshLeagueListInteractorTest {

    @Mock
    private LeagueGateway leagueGateway;

    @Mock
    private LeagueSyncGateway leagueSyncGateway;

    @Mock
    private RefreshLeagueListOutputBoundary outputBoundary;

    @Test
    void refreshLeagueList_fetchesLiveThenSyncsIntoTheCache_presentingTheSyncedResult() {
        League fetched = new League(null, "Allflame", "Allflame", true, false);
        League synced = new League(1L, "Allflame", "Allflame", true, true); // hasExchangeActivity preserved by sync
        when(leagueGateway.fetchLeagues()).thenReturn(List.of(fetched));
        when(leagueSyncGateway.upsertFromGgg(List.of(fetched))).thenReturn(List.of(synced));

        new RefreshLeagueListInteractor(leagueGateway, leagueSyncGateway, outputBoundary).refreshLeagueList();

        ArgumentCaptor<RefreshLeagueListResponseModel> captor =
                ArgumentCaptor.forClass(RefreshLeagueListResponseModel.class);
        verify(outputBoundary).present(captor.capture());
        assertThat(captor.getValue().leagues()).containsExactly(synced);
    }

    @Test
    void refreshLeagueList_noLeaguesFromGgg_presentsEmptyListWithoutCallingSync() {
        when(leagueGateway.fetchLeagues()).thenReturn(List.of());
        when(leagueSyncGateway.upsertFromGgg(anyList())).thenReturn(List.of());

        new RefreshLeagueListInteractor(leagueGateway, leagueSyncGateway, outputBoundary).refreshLeagueList();

        ArgumentCaptor<RefreshLeagueListResponseModel> captor =
                ArgumentCaptor.forClass(RefreshLeagueListResponseModel.class);
        verify(outputBoundary).present(captor.capture());
        assertThat(captor.getValue().leagues()).isEmpty();
    }
}
