package com.poeflipfinder.backend.framework.league;

/**
 * Thrown the moment the Leagues API response doesn't match the expected
 * shape -- fail loudly at the boundary, per docs/ARCHITECTURE.md § 2 and
 * docs/CODE_STYLE.md § Error Handling.
 */
public class LeagueGatewayException extends RuntimeException {

    public LeagueGatewayException(String message, Throwable cause) {
        super(message, cause);
    }
}
