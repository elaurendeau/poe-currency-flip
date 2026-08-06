package com.poeflipfinder.backend.framework.itemicon;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.Currency;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

/**
 * Contract test per docs/ARCHITECTURE.md § 3: a saved real Item Icons
 * response in, an asserted resolved (or unresolved) Currency out. Fixture
 * captured from the real live endpoint on 2026-08-06.
 */
class GggItemIconGatewayTest {

    private final GggItemIconGateway gateway = new GggItemIconGateway(RestClient.builder());

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

    private String fixture() {
        try {
            Path path = Path.of("src/test/resources/fixtures/item-icons-response.json");
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
