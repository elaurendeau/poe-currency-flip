package com.poeflipfinder.backend.framework.web;

import com.poeflipfinder.backend.controller.LeagueController;
import com.poeflipfinder.backend.framework.web.generated.api.LeaguesApi;
import com.poeflipfinder.backend.framework.web.generated.model.League;
import com.poeflipfinder.backend.gateway.LeagueGateway;
import com.poeflipfinder.backend.presenter.LeagueViewModel;
import com.poeflipfinder.backend.presenter.ResolveLeagueListPresenter;
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
 */
@RestController
public class LeagueRestController implements LeaguesApi {

    private final LeagueGateway leagueGateway;

    public LeagueRestController(LeagueGateway leagueGateway) {
        this.leagueGateway = leagueGateway;
    }

    @Override
    public ResponseEntity<List<League>> getLeagues() {
        ResolveLeagueListPresenter presenter = new ResolveLeagueListPresenter();
        ResolveLeagueListInteractor interactor = new ResolveLeagueListInteractor(leagueGateway, presenter);
        LeagueController controller = new LeagueController(interactor);

        controller.resolveLeagueList();

        List<League> contractLeagues = presenter.viewModel().stream()
                .map(this::toContractModel)
                .toList();
        return ResponseEntity.ok(contractLeagues);
    }

    private League toContractModel(LeagueViewModel viewModel) {
        return new League(viewModel.id(), viewModel.name(), viewModel.isDefault());
    }
}
