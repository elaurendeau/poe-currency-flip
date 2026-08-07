package com.poeflipfinder.backend.framework.web;

import com.poeflipfinder.backend.controller.LeagueController;
import com.poeflipfinder.backend.controller.RefreshLeagueListController;
import com.poeflipfinder.backend.framework.web.generated.api.LeaguesApi;
import com.poeflipfinder.backend.framework.web.generated.model.League;
import com.poeflipfinder.backend.gateway.LeagueGateway;
import com.poeflipfinder.backend.gateway.LeagueQueryGateway;
import com.poeflipfinder.backend.gateway.LeagueSyncGateway;
import com.poeflipfinder.backend.presenter.LeagueViewModel;
import com.poeflipfinder.backend.presenter.RefreshLeagueListPresenter;
import com.poeflipfinder.backend.presenter.ResolveLeagueListPresenter;
import com.poeflipfinder.backend.usecase.refreshleaguelist.RefreshLeagueListInteractor;
import com.poeflipfinder.backend.usecase.resolveleaguelist.ResolveLeagueListInteractor;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * Implements the contracts/openapi.yaml-generated LeaguesApi interface, so a
 * response shape that no longer matches the contract fails to compile (see
 * docs/ARCHITECTURE.md § API Contract). Wires Controller+Presenter+Interactor
 * together per request (docs/CODE_STYLE.md § Clean Architecture, outermost
 * ring) -- the Presenter holds per-request state, so it is built fresh here
 * rather than injected as a singleton bean.
 *
 * <p>getLeagues is a cached DB read (LeagueQueryGateway); refreshLeagues is
 * the only path that calls GGG's live Leagues API (LeagueGateway) and syncs
 * the result into the cache (LeagueSyncGateway) -- see docs/PRD.md § 7.7.
 */
@RestController
public class LeagueRestController implements LeaguesApi {

    private final LeagueQueryGateway leagueQueryGateway;
    private final LeagueGateway leagueGateway;
    private final LeagueSyncGateway leagueSyncGateway;

    public LeagueRestController(
            LeagueQueryGateway leagueQueryGateway, LeagueGateway leagueGateway, LeagueSyncGateway leagueSyncGateway) {
        this.leagueQueryGateway = leagueQueryGateway;
        this.leagueGateway = leagueGateway;
        this.leagueSyncGateway = leagueSyncGateway;
    }

    @Override
    public ResponseEntity<List<League>> getLeagues() {
        ResolveLeagueListPresenter presenter = new ResolveLeagueListPresenter();
        ResolveLeagueListInteractor interactor = new ResolveLeagueListInteractor(leagueQueryGateway, presenter);
        LeagueController controller = new LeagueController(interactor);

        controller.resolveLeagueList();

        return ResponseEntity.ok(toContractModels(presenter.viewModel()));
    }

    @Override
    public ResponseEntity<List<League>> refreshLeagues() {
        RefreshLeagueListPresenter presenter = new RefreshLeagueListPresenter();
        RefreshLeagueListInteractor interactor =
                new RefreshLeagueListInteractor(leagueGateway, leagueSyncGateway, presenter);
        RefreshLeagueListController controller = new RefreshLeagueListController(interactor);

        controller.refreshLeagueList();

        return ResponseEntity.ok(toContractModels(presenter.viewModel()));
    }

    private List<League> toContractModels(List<LeagueViewModel> viewModels) {
        return viewModels.stream().map(this::toContractModel).toList();
    }

    private League toContractModel(LeagueViewModel viewModel) {
        return new League(viewModel.id(), viewModel.name(), viewModel.isDefault());
    }
}
