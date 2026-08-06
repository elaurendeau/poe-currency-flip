package com.poeflipfinder.backend.usecase.computeflipopportunities;

import com.poeflipfinder.backend.entity.FlipOpportunity;
import java.util.List;

public record ComputeFlipOpportunitiesResponseModel(List<FlipOpportunity> opportunities) {
}
