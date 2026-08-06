package com.poeflipfinder.backend.usecase.getingestionfreshness;

import com.poeflipfinder.backend.gateway.IngestionFreshness;
import com.poeflipfinder.backend.gateway.SnapshotRepositoryGateway;

/**
 * A simple pass-through read with no formatting logic -- exempted from the
 * full Presenter/Boundary ceremony per docs/CODE_STYLE.md's pragmatic note
 * on Clean Architecture layering.
 */
public class GetIngestionFreshnessInteractor implements GetIngestionFreshnessInputBoundary {

    private final SnapshotRepositoryGateway snapshotRepositoryGateway;

    public GetIngestionFreshnessInteractor(SnapshotRepositoryGateway snapshotRepositoryGateway) {
        this.snapshotRepositoryGateway = snapshotRepositoryGateway;
    }

    @Override
    public IngestionFreshnessResponseModel getIngestionFreshness() {
        IngestionFreshness freshness = snapshotRepositoryGateway.readIngestionState();
        return new IngestionFreshnessResponseModel(
                freshness.lastProcessedChangeId(), freshness.activeGenerationRefreshedAt());
    }
}
