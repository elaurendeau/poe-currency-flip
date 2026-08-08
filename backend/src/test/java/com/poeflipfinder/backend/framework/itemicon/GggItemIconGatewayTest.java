package com.poeflipfinder.backend.framework.itemicon;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.Currency;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * Contract test per docs/ARCHITECTURE.md § 3: a saved real Item Icons
 * response in, an asserted resolved (or unresolved) Currency out. Fixture
 * captured from the real live endpoint on 2026-08-06.
 */
class GggItemIconGatewayTest {

    private final GggItemIconGateway gateway = new GggItemIconGateway();

    @Test
    void lookupItem_loadsTheRealBundledCatalogResource_withoutAnyLiveHttpCall() {
        // Regression test: this gateway used to fetch live over HTTP; every
        // other test here calls normalize(fixture()) directly and never
        // exercises the actual resource-loading path added when both
        // www.pathofexile.com and its CDN mirror started returning 403 from
        // production (docs/DATA_SOURCES.md § Item Icons). Deliberately does
        // NOT call normalize() first, so this only passes if
        // reference-data/item-icons-catalog.json is present on the
        // classpath and actually parses.
        Optional<Currency> result = gateway.lookupItem("Metadata/Items/Currency/CurrencyPortal");

        assertThat(result).isPresent();
        assertThat(result.get().displayName()).isEqualTo("Portal Scroll");
    }

    @Test
    void lookupItem_resolvesACurrency_viaTheImageFilenameBasename_notTheIdField() {
        gateway.normalize(fixture());

        Optional<Currency> result = gateway.lookupItem("Metadata/Items/Currency/CurrencyPortal");

        assertThat(result).isPresent();
        assertThat(result.get().displayName()).isEqualTo("Portal Scroll");
        assertThat(result.get().itemType()).isEqualTo(Currency.ItemType.CURRENCY);
        assertThat(result.get().iconUrl()).startsWith("https://www.pathofexile.com/gen/image/");
        assertThat(result.get().externalId()).isEqualTo("Metadata/Items/Currency/CurrencyPortal");
    }

    @Test
    void lookupItem_resolvesADivinationCard_viaNormalizedTextComparison_withNoIconUrl() {
        gateway.normalize(fixture());

        Optional<Currency> result =
                gateway.lookupItem("Metadata/Items/DivinationCards/DivinationCardTheApothecary");

        assertThat(result).isPresent();
        assertThat(result.get().displayName()).isEqualTo("The Apothecary");
        assertThat(result.get().itemType()).isEqualTo(Currency.ItemType.DIVINATION_CARD);
        assertThat(result.get().iconUrl()).isNull();
    }

    @Test
    void lookupItem_returnsEmpty_forAnItemNotInTheCatalog() {
        gateway.normalize(fixture());

        // Verified real example (docs/DATA_SOURCES.md § Item Icons): this
        // item genuinely has no catalog entry in any group.
        Optional<Currency> result =
                gateway.lookupItem("Metadata/Items/Currency/CurrencyBreachUpgradeUniqueGeneral");

        assertThat(result).isEmpty();
    }

    @Test
    void lookupItem_resolvesAnEssence_byFallingBackToASuffixMatch() {
        gateway.normalize(fixture());

        // Real example verified against live Currency Exchange data
        // 2026-08-07: the catalog's image basename for essences omits the
        // "CurrencyEssence" prefix that the real item path keeps, so the
        // exact-match lookup misses and must fall back to a suffix match.
        Optional<Currency> result = gateway.lookupItem("Metadata/Items/Currency/CurrencyEssenceHatred5");

        assertThat(result).isPresent();
        assertThat(result.get().displayName()).isEqualTo("Screaming Essence of Hatred");
        assertThat(result.get().itemType()).isEqualTo(Currency.ItemType.CURRENCY);
    }

    @Test
    void lookupItem_resolvesMavensWrit_byFallingBackToASuffixMatch() {
        gateway.normalize(fixture());

        // Real example verified 2026-08-07: catalog basename "MavenKey" vs.
        // real basename "CurrencyMavenKey" -- only the "Currency" prefix is
        // dropped here, unlike the longer prefix essences drop.
        Optional<Currency> result = gateway.lookupItem("Metadata/Items/MapFragments/CurrencyMavenKey");

        assertThat(result).isPresent();
        assertThat(result.get().displayName()).isEqualTo("The Maven's Writ");
    }

    @Test
    void lookupItem_doesNotSuffixMatch_whenTheOnlyCandidateIsShorterThanTheMinimumLength() {
        gateway.normalize(fixture());

        // The fixture's "Misc" group has a 3-character basename ("Tal")
        // that this real path's basename ends in -- proves
        // MIN_SUFFIX_MATCH_LENGTH actually suppresses a match that would
        // otherwise succeed, not just that unrelated items stay unmatched.
        Optional<Currency> result = gateway.lookupItem("Metadata/Items/Currency/CurrencyFooBarTal");

        assertThat(result).isEmpty();
    }

    private String fixture() {
        try {
            Path path = Path.of("src/test/resources/fixtures/item-icons-response.json");
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
