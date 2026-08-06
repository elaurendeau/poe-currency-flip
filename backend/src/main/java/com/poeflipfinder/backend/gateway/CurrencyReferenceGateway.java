package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.Currency;
import java.util.Optional;

/**
 * Defined by the use-case ring: resolve a Currency Exchange item path to a
 * persisted Currency row, creating one on first sight via ItemIconGateway.
 * Empty means the item genuinely can't be resolved even there -- the
 * interactor treats that as skip-this-pair, not a run failure (see
 * docs/ARCHITECTURE.md § Currency Exchange Ingestion).
 */
public interface CurrencyReferenceGateway {

    Optional<Currency> resolveOrCreateCurrency(String externalId);
}
