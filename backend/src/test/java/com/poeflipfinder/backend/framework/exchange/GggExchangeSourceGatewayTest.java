package com.poeflipfinder.backend.framework.exchange;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.gateway.ExchangeChangeStreamPage;
import com.poeflipfinder.backend.gateway.ExchangeMarketEntry;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

/**
 * Contract test per docs/ARCHITECTURE.md § 3: a saved real API response in,
 * an asserted normalized domain object out. Fixtures were captured from the
 * real live endpoint on 2026-08-06 (see docs/DATA_SOURCES.md § Currency
 * Exchange Data for the verified facts these assertions rely on).
 */
class GggExchangeSourceGatewayTest {

    private static final long REQUESTED_CHANGE_ID = 1785985200L;

    private final GggExchangeSourceGateway gateway = new GggExchangeSourceGateway(RestClient.builder());

    @Test
    void normalize_parsesAllMarketEntries_regardlessOfItemCategory() {
        ExchangeChangeStreamPage page = gateway.normalize(fixture("currency-exchange-hour-response.json"), REQUESTED_CHANGE_ID, false);

        assertThat(page.atTip()).isFalse();
        assertThat(page.nextChangeId()).isEqualTo(1785988800L);
        assertThat(page.entries()).hasSize(4);
        assertThat(page.entries())
                .extracting(ExchangeMarketEntry::currencyAExternalId)
                .containsExactlyInAnyOrder(
                        "Metadata/Items/Currency/CurrencyBreachUpgradeUniqueGeneral",
                        "Metadata/Items/Currency/CurrencyJewelleryQualityVaal",
                        "Metadata/Items/DivinationCards/DivinationCardTheApothecary",
                        "Metadata/Items/AtlasExiles/AddModToRareCrusader");
    }

    @Test
    void normalize_pullsPerSideValuesFromTheCorrectItemPathKey() {
        ExchangeChangeStreamPage page = gateway.normalize(fixture("currency-exchange-hour-response.json"), REQUESTED_CHANGE_ID, false);

        ExchangeMarketEntry cardEntry = page.entries().stream()
                .filter(e -> e.currencyAExternalId().contains("DivinationCard"))
                .findFirst()
                .orElseThrow();

        assertThat(cardEntry.leagueExternalId()).isEqualTo("Standard");
        assertThat(cardEntry.currencyBExternalId()).isEqualTo("Metadata/Items/Currency/CurrencyModValues");
        assertThat(cardEntry.volumeTradedA()).isEqualTo(2);
        assertThat(cardEntry.volumeTradedB()).isEqualTo(80);
        assertThat(cardEntry.lowestStockA()).isEqualTo(203);
        assertThat(cardEntry.highestStockA()).isEqualTo(210);
        assertThat(cardEntry.lowestRatioA()).isEqualTo(1);
        assertThat(cardEntry.highestRatioB()).isEqualTo(40);
        assertThat(cardEntry.snapshotHour()).isEqualTo(Instant.ofEpochSecond(REQUESTED_CHANGE_ID));
    }

    @Test
    void normalize_atTip_returnsNoEntries_butStillReportsNextChangeId() {
        ExchangeChangeStreamPage page = gateway.normalize(fixture("currency-exchange-tip-response.json"), 1785988800L, true);

        assertThat(page.atTip()).isTrue();
        assertThat(page.entries()).isEmpty();
        assertThat(page.nextChangeId()).isEqualTo(1785988800L);
    }

    private String fixture(String filename) {
        try {
            Path path = Path.of("src/test/resources/fixtures/" + filename);
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
