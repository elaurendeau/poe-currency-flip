package com.poeflipfinder.backend.framework.web;

import com.poeflipfinder.backend.controller.GetIngestionFreshnessController;
import com.poeflipfinder.backend.controller.RefreshExchangeIngestionController;
import com.poeflipfinder.backend.framework.web.generated.api.ExchangeIngestionApi;
import com.poeflipfinder.backend.framework.web.generated.model.IngestionFreshness;
import com.poeflipfinder.backend.framework.web.generated.model.IngestionRefreshResult;
import com.poeflipfinder.backend.gateway.CurrencyReferenceGateway;
import com.poeflipfinder.backend.gateway.ExchangeSourceGateway;
import com.poeflipfinder.backend.gateway.LeagueReferenceGateway;
import com.poeflipfinder.backend.gateway.SnapshotRepositoryGateway;
import com.poeflipfinder.backend.presenter.IngestionRefreshViewModel;
import com.poeflipfinder.backend.presenter.RunIngestionCatchupPresenter;
import com.poeflipfinder.backend.usecase.getingestionfreshness.GetIngestionFreshnessInteractor;
import com.poeflipfinder.backend.usecase.getingestionfreshness.IngestionFreshnessResponseModel;
import com.poeflipfinder.backend.usecase.runingestioncatchup.CatchupCapPolicy;
import com.poeflipfinder.backend.usecase.runingestioncatchup.RunIngestionCatchupInteractor;
import java.time.Clock;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * Implements the contracts/openapi.yaml-generated ExchangeIngestionApi
 * interface, so a response shape that no longer matches the contract fails
 * to compile. Mirrors LeagueRestController's per-request wiring --
 * interactors hold per-request state, so they're built fresh here rather
 * than injected as singleton beans.
 */
@RestController
public class ExchangeIngestionRestController implements ExchangeIngestionApi {

    private final ExchangeSourceGateway exchangeSourceGateway;
    private final SnapshotRepositoryGateway snapshotRepositoryGateway;
    private final CurrencyReferenceGateway currencyReferenceGateway;
    private final LeagueReferenceGateway leagueReferenceGateway;
    private final Clock clock;
    private final CatchupCapPolicy capPolicy;

    public ExchangeIngestionRestController(
            ExchangeSourceGateway exchangeSourceGateway,
            SnapshotRepositoryGateway snapshotRepositoryGateway,
            CurrencyReferenceGateway currencyReferenceGateway,
            LeagueReferenceGateway leagueReferenceGateway,
            Clock clock,
            @Value("${app.ingestion.max-hours-per-call}") int maxHoursPerCall,
            @Value("${app.ingestion.first-run-lookback-hours}") int firstRunLookbackHours) {
        this.exchangeSourceGateway = exchangeSourceGateway;
        this.snapshotRepositoryGateway = snapshotRepositoryGateway;
        this.currencyReferenceGateway = currencyReferenceGateway;
        this.leagueReferenceGateway = leagueReferenceGateway;
        this.clock = clock;
        this.capPolicy = new CatchupCapPolicy(maxHoursPerCall, Duration.ofHours(firstRunLookbackHours));
    }

    @Override
    public ResponseEntity<IngestionRefreshResult> refreshExchangeIngestion() {
        RunIngestionCatchupPresenter presenter = new RunIngestionCatchupPresenter();
        RunIngestionCatchupInteractor interactor = new RunIngestionCatchupInteractor(
                exchangeSourceGateway,
                snapshotRepositoryGateway,
                currencyReferenceGateway,
                leagueReferenceGateway,
                presenter,
                clock,
                capPolicy);
        RefreshExchangeIngestionController controller = new RefreshExchangeIngestionController(interactor);

        controller.refreshExchangeIngestion();

        return ResponseEntity.ok(toContractModel(presenter.viewModel()));
    }

    @Override
    public ResponseEntity<IngestionFreshness> getExchangeIngestionFreshness() {
        GetIngestionFreshnessInteractor interactor = new GetIngestionFreshnessInteractor(snapshotRepositoryGateway);
        GetIngestionFreshnessController controller = new GetIngestionFreshnessController(interactor);

        IngestionFreshnessResponseModel response = controller.getIngestionFreshness();

        return ResponseEntity.ok(toContractModel(response));
    }

    private IngestionRefreshResult toContractModel(IngestionRefreshViewModel viewModel) {
        return new IngestionRefreshResult(
                        viewModel.hoursProcessed(),
                        viewModel.fullyCaughtUp(),
                        viewModel.skippedUnresolvableMarketEntryCount())
                .lastProcessedChangeId(viewModel.lastProcessedChangeId());
    }

    private IngestionFreshness toContractModel(IngestionFreshnessResponseModel response) {
        OffsetDateTime refreshedAt = response.activeGenerationRefreshedAt() == null
                ? null
                : response.activeGenerationRefreshedAt().atOffset(ZoneOffset.UTC);
        return new IngestionFreshness()
                .lastProcessedChangeId(response.lastProcessedChangeId())
                .activeGenerationRefreshedAt(refreshedAt);
    }
}
