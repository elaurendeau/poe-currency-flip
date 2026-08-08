package com.poeflipfinder.backend.framework.divinationcard;

/**
 * Thrown when the bundled divination card catalog is missing or doesn't
 * match the expected shape -- fail loudly at the boundary, per
 * docs/ARCHITECTURE.md § 2 and docs/CODE_STYLE.md § Error Handling.
 */
public class DivinationCardReferenceGatewayException extends RuntimeException {

    public DivinationCardReferenceGatewayException(String message, Throwable cause) {
        super(message, cause);
    }
}
