package com.poeflipfinder.backend.framework.exchange;

/**
 * Thrown on a network failure or a Currency Exchange response that doesn't
 * match the expected shape -- fail loudly at the boundary, per
 * docs/ARCHITECTURE.md § 2 and docs/CODE_STYLE.md § Error Handling. The
 * expected "at tip" 404 is not this -- see GggExchangeSourceGateway.
 */
public class ExchangeSourceGatewayException extends RuntimeException {

    public ExchangeSourceGatewayException(String message, Throwable cause) {
        super(message, cause);
    }
}
