package com.poeflipfinder.backend.framework.itemicon;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.gateway.ItemIconGateway;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.core.io.ClassPathResource;

/**
 * The Frameworks & Drivers implementation of ItemIconGateway, reading GGG's
 * public Item Icons static-data (docs/DATA_SOURCES.md § Item Icons) from a
 * bundled resource rather than fetching it live. Both
 * www.pathofexile.com/api/trade/data/static and its CDN mirror
 * web.poecdn.com/api/trade/data/static return HTTP 403 from Render's IP --
 * confirmed live 2026-08-06 that the block is on the {@code /api/trade/*}
 * path itself (the same stricter-rate-limited trade-search family noted in
 * DATA_SOURCES.md), not the hostname. Since this catalog is static,
 * rarely-changing data (same treatment as the vendor-recipe reference data
 * in DATA_SOURCES.md § Vendor Sell Rates & Recipes), it's captured once into
 * {@code reference-data/item-icons-catalog.json} and refreshed manually --
 * see that doc section for the refresh procedure.
 *
 * <p>The match key against a Currency Exchange item path is <b>not</b> the
 * catalog's {@code id} field (a short trade-UI slug unrelated to the
 * metadata path) -- it's the filename tail of the {@code image} URL for most
 * items, or a normalized comparison against {@code text} for divination
 * cards (which have no {@code image} field at all). Both verified by direct
 * testing 2026-08-06; see docs/DATA_SOURCES.md § Item Icons.
 */
public class GggItemIconGateway implements ItemIconGateway {

    private static final String DIVINATION_CARD_PREFIX = "DivinationCard";
    private static final String CATALOG_RESOURCE_PATH = "reference-data/item-icons-catalog.json";

    private final ObjectMapper objectMapper;
    private Map<String, RawEntry> entriesByImageBasename;
    private Map<String, RawEntry> cardEntriesByCanonicalName;

    public GggItemIconGateway() {
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public Optional<Currency> lookupItem(String externalId) {
        ensureCatalogLoaded();
        String basename = basenameOf(externalId);

        if (basename.startsWith(DIVINATION_CARD_PREFIX)) {
            return lookupCard(externalId, basename);
        }
        return lookupCurrency(externalId, basename);
    }

    private Optional<Currency> lookupCurrency(String externalId, String basename) {
        RawEntry entry = entriesByImageBasename.get(basename);
        if (entry == null) {
            return Optional.empty();
        }
        return Optional.of(new Currency(
                null, externalId, entry.text(), toAbsoluteIconUrl(entry.image()), Currency.ItemType.CURRENCY));
    }

    private Optional<Currency> lookupCard(String externalId, String basename) {
        String cardName = basename.substring(DIVINATION_CARD_PREFIX.length());
        RawEntry entry = cardEntriesByCanonicalName.get(canonicalize(cardName));
        if (entry == null) {
            return Optional.empty();
        }
        return Optional.of(new Currency(null, externalId, entry.text(), null, Currency.ItemType.DIVINATION_CARD));
    }

    private synchronized void ensureCatalogLoaded() {
        if (entriesByImageBasename != null) {
            return;
        }
        normalize(readBundledCatalog());
    }

    private String readBundledCatalog() {
        try (InputStream in = new ClassPathResource(CATALOG_RESOURCE_PATH).getInputStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new ItemIconGatewayException("Failed to read bundled Item Icons catalog " + CATALOG_RESOURCE_PATH, e);
        }
    }

    /** Package-visible so the contract test can exercise parsing without a live HTTP call. */
    void normalize(String json) {
        RawCatalog catalog = deserialize(json);
        Map<String, RawEntry> byBasename = new HashMap<>();
        Map<String, RawEntry> cardsByCanonicalName = new HashMap<>();
        for (RawGroup group : catalog.result()) {
            for (RawEntry entry : group.entries()) {
                if (entry.image() != null) {
                    byBasename.put(basenameOfImage(entry.image()), entry);
                } else if ("Cards".equals(group.id())) {
                    cardsByCanonicalName.put(canonicalize(entry.text()), entry);
                }
            }
        }
        this.entriesByImageBasename = byBasename;
        this.cardEntriesByCanonicalName = cardsByCanonicalName;
    }

    private RawCatalog deserialize(String json) {
        try {
            return objectMapper.readValue(json, RawCatalog.class);
        } catch (IOException e) {
            throw new ItemIconGatewayException("Failed to parse Item Icons response", e);
        }
    }

    private String basenameOf(String externalId) {
        int lastSlash = externalId.lastIndexOf('/');
        return lastSlash >= 0 ? externalId.substring(lastSlash + 1) : externalId;
    }

    private String basenameOfImage(String image) {
        String filename = image.substring(image.lastIndexOf('/') + 1);
        return filename.endsWith(".png") ? filename.substring(0, filename.length() - 4) : filename;
    }

    private String canonicalize(String text) {
        return text.replace(" ", "").toLowerCase();
    }

    private String toAbsoluteIconUrl(String relativePath) {
        return "https://www.pathofexile.com" + relativePath;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawCatalog(List<RawGroup> result) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawGroup(String id, String label, List<RawEntry> entries) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawEntry(String id, String text, String image) {
    }
}
