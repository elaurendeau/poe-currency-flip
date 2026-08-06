package com.poeflipfinder.backend.framework.itemicon;

/**
 * Thrown on a network failure or an Item Icons response that doesn't match
 * the expected shape -- fail loudly at the boundary, per
 * docs/ARCHITECTURE.md § 2 and docs/CODE_STYLE.md § Error Handling.
 */
public class ItemIconGatewayException extends RuntimeException {

    public ItemIconGatewayException(String message, Throwable cause) {
        super(message, cause);
    }
}
