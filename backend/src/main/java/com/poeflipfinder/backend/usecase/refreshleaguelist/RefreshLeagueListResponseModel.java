package com.poeflipfinder.backend.usecase.refreshleaguelist;

import com.poeflipfinder.backend.entity.League;
import java.util.List;

/** Plain data holder passed to the Output Boundary -- not the entity, not the DTO. */
public record RefreshLeagueListResponseModel(List<League> leagues) {}
