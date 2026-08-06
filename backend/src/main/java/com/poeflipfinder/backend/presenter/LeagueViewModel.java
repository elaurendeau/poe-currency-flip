package com.poeflipfinder.backend.presenter;

/** JSON-ready shape for one league in the Feature D dropdown (docs/PRD.md § 7.4). */
public record LeagueViewModel(String id, String name, boolean isDefault) {
}
