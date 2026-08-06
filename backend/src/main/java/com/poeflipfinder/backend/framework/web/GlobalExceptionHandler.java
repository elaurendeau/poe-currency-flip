package com.poeflipfinder.backend.framework.web;

import com.poeflipfinder.backend.framework.exchange.ExchangeSourceGatewayException;
import com.poeflipfinder.backend.framework.itemicon.ItemIconGatewayException;
import com.poeflipfinder.backend.framework.league.LeagueGatewayException;
import java.time.Instant;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Centralizes the one place unchecked gateway failures get mapped to an
 * HTTP response, per docs/CODE_STYLE.md § Error Handling ("let them
 * propagate to one centralized handler"). Maps to 502 (Bad Gateway) since
 * these all represent an upstream external source failing or returning an
 * unexpected shape, not a fault in this app's own request handling.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler({
        ExchangeSourceGatewayException.class,
        ItemIconGatewayException.class,
        LeagueGatewayException.class
    })
    public ResponseEntity<Map<String, Object>> handleUpstreamGatewayFailure(RuntimeException e) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(Map.of(
                        "error", "upstream_source_failure",
                        "message", e.getMessage(),
                        "timestamp", Instant.now().toString()));
    }
}
