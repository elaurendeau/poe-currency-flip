package com.poeflipfinder.backend.gateway;

import com.poeflipfinder.backend.entity.Currency;
import java.util.Optional;

/**
 * Defined by the use-case ring for whatever it needs from GGG's Item Icons
 * static-data endpoint (docs/DATA_SOURCES.md § Item Icons) -- resolving a
 * never-before-seen Currency Exchange item path into a display name, icon
 * URL, and item type. Not every path resolves (docs/DATA_SOURCES.md notes
 * confirmed real examples with no catalog entry at all) -- that's an
 * expected outcome, not a failure.
 */
public interface ItemIconGateway {

    Optional<Currency> lookupItem(String externalId);
}
