package com.poeflipfinder.backend.usecase.resolveleaguelist;

import com.poeflipfinder.backend.entity.League;
import java.util.List;

/** Plain data holder passed to the Output Boundary -- not the entity, not the DTO. */
public record ResolveLeagueListResponseModel(List<League> leagues) {
}
