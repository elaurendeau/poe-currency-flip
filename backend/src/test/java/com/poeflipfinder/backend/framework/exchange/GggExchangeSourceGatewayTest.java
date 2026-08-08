package com.poeflipfinder.backend.framework.exchange;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.gateway.ExchangeChangeStreamPage;
import com.poeflipfinder.backend.gateway.ExchangeMarketEntry;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

/**
 * Contract test per docs/ARCHITECTURE.md § 3: a saved real API response in,
 * an asserted normalized domain object out. The fixture is a genuinely real,
 * complete capture (2,164 market entries, ~1.8MB) from
 * {@code https://web.poecdn.com/api/currency-exchange/1786150800}, captured
 * 2026-08-08 -- not a hand-trimmed sample. This specific hour was chosen
 * because it's the one that exposed a real production bug: The Sephirot
 * genuinely trades (real volume, real stock) but was silently dropped by
 * DivinationCardOpportunityFinder's pricing math (see that class's
 * docstring). Asserting on this exact real entry here, and again end-to-end
 * in DivinationCardOpportunityFinderIntegrationTest, is the regression guard
 * for that incident.
 */
class GggExchangeSourceGatewayTest {

    private static final long REQUESTED_CHANGE_ID = 1786150800L;

    private final GggExchangeSourceGateway gateway = new GggExchangeSourceGateway(RestClient.builder());

    @Test
    void normalize_parsesTheFullRealHour_withoutError() {
        ExchangeChangeStreamPage page = gateway.normalize(fixture("currency-exchange-hour-response.json"), REQUESTED_CHANGE_ID, false);

        assertThat(page.atTip()).isFalse();
        assertThat(page.nextChangeId()).isEqualTo(1786154400L);
        // Real hour, real diversity -- not a hand-picked handful. Asserting a
        // realistic minimum rather than an exact count keeps this from being
        // as brittle as re-pinning the fixture's precise size on every refresh.
        assertThat(page.entries()).hasSizeGreaterThan(2000);
        assertThat(page.entries())
                .extracting(ExchangeMarketEntry::currencyAExternalId)
                .anyMatch(id -> id.startsWith("Metadata/Items/Currency/"))
                .anyMatch(id -> id.startsWith("Metadata/Items/DivinationCards/"));
    }

    @Test
    void normalize_pullsPerSideValuesFromTheCorrectItemPathKey_forARealDivinationCardEntry() {
        ExchangeChangeStreamPage page = gateway.normalize(fixture("currency-exchange-hour-response.json"), REQUESTED_CHANGE_ID, false);

        // The exact real entry behind the Sephirot production incident --
        // verified against the raw GGG response directly, not hand-shaped.
        ExchangeMarketEntry sephirotVsChaos = findEntry(
                page.entries(),
                "Metadata/Items/DivinationCards/DivinationCardTheSephirot",
                "Metadata/Items/Currency/CurrencyRerollRare",
                "Allflame");

        assertThat(sephirotVsChaos.volumeTradedA()).isEqualTo(546);
        assertThat(sephirotVsChaos.volumeTradedB()).isEqualTo(109576);
        assertThat(sephirotVsChaos.lowestStockA()).isEqualTo(3);
        assertThat(sephirotVsChaos.highestStockA()).isEqualTo(74);
        assertThat(sephirotVsChaos.lowestStockB()).isEqualTo(28382);
        assertThat(sephirotVsChaos.highestStockB()).isEqualTo(110790);
        assertThat(sephirotVsChaos.lowestRatioA()).isEqualTo(1);
        assertThat(sephirotVsChaos.highestRatioA()).isEqualTo(1);
        assertThat(sephirotVsChaos.lowestRatioB()).isEqualTo(217);
        assertThat(sephirotVsChaos.highestRatioB()).isEqualTo(188);
        assertThat(sephirotVsChaos.snapshotHour()).isEqualTo(Instant.ofEpochSecond(REQUESTED_CHANGE_ID));
    }

    @Test
    void normalize_atTip_returnsNoEntries_butStillReportsNextChangeId() {
        ExchangeChangeStreamPage page = gateway.normalize(fixture("currency-exchange-tip-response.json"), 1785988800L, true);

        assertThat(page.atTip()).isTrue();
        assertThat(page.entries()).isEmpty();
        assertThat(page.nextChangeId()).isEqualTo(1785988800L);
    }

    private ExchangeMarketEntry findEntry(
            List<ExchangeMarketEntry> entries, String currencyAExternalId, String currencyBExternalId, String league) {
        return entries.stream()
                .filter(e -> currencyAExternalId.equals(e.currencyAExternalId())
                        && currencyBExternalId.equals(e.currencyBExternalId())
                        && league.equals(e.leagueExternalId()))
                .findFirst()
                .orElseThrow(() -> new AssertionError(
                        "No entry for " + currencyAExternalId + "|" + currencyBExternalId + " in " + league));
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
