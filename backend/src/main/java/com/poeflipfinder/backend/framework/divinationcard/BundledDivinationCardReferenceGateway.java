package com.poeflipfinder.backend.framework.divinationcard;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.DivinationCardReward;
import com.poeflipfinder.backend.gateway.DivinationCardReferenceGateway;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.springframework.core.io.ClassPathResource;

/**
 * The Frameworks & Drivers implementation of DivinationCardReferenceGateway,
 * reading the manually-captured divination card reward data (docs/DATA_SOURCES.md
 * § Divination Card Turn-In Rewards) from a bundled resource -- same treatment
 * as {@link com.poeflipfinder.backend.framework.itemicon.GggItemIconGateway}'s
 * Item Icons catalog, since neither source has a live API to fetch from.
 *
 * <p>The {@code card}/{@code rewardCurrency} fields of the returned
 * {@link DivinationCardReward} entities are name-only placeholders (no id,
 * externalId, or iconUrl) -- this gateway has no access to live Currency
 * Exchange data to resolve those against. Callers must match by
 * {@link Currency#displayName()} against currently-active market snapshots to
 * get a fully-resolved Currency before using one in a FlipOpportunity.
 */
public class BundledDivinationCardReferenceGateway implements DivinationCardReferenceGateway {

    private static final String CATALOG_RESOURCE_PATH = "reference-data/divination-card-rewards.json";

    private final ObjectMapper objectMapper;
    private List<DivinationCardReward> cardRewards;

    public BundledDivinationCardReferenceGateway() {
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public List<DivinationCardReward> findAll() {
        ensureCatalogLoaded();
        return cardRewards;
    }

    private synchronized void ensureCatalogLoaded() {
        if (cardRewards != null) {
            return;
        }
        normalize(readBundledCatalog());
    }

    private String readBundledCatalog() {
        try (InputStream in = new ClassPathResource(CATALOG_RESOURCE_PATH).getInputStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new DivinationCardReferenceGatewayException(
                    "Failed to read bundled divination card catalog " + CATALOG_RESOURCE_PATH, e);
        }
    }

    /** Package-visible so a test can exercise parsing without touching the classpath resource. */
    void normalize(String json) {
        List<RawEntry> entries = deserialize(json);
        cardRewards = entries.stream().map(this::toDomain).toList();
    }

    private List<RawEntry> deserialize(String json) {
        try {
            return objectMapper.readValue(json, objectMapper.getTypeFactory().constructCollectionType(List.class, RawEntry.class));
        } catch (IOException e) {
            throw new DivinationCardReferenceGatewayException("Failed to parse divination card catalog", e);
        }
    }

    private DivinationCardReward toDomain(RawEntry entry) {
        Currency card = new Currency(null, null, entry.cardName(), null, Currency.ItemType.DIVINATION_CARD);
        Currency rewardCurrency = entry.rewardCurrencyName() == null
                ? null
                : new Currency(null, null, entry.rewardCurrencyName(), null, Currency.ItemType.CURRENCY);
        int rewardQuantity = entry.rewardQuantity() == null ? 0 : entry.rewardQuantity();
        return new DivinationCardReward(card, entry.stackSize(), rewardCurrency, rewardQuantity, entry.isPredictable());
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record RawEntry(
            String cardName, int stackSize, String rewardCurrencyName, Integer rewardQuantity, boolean isPredictable) {
    }
}
