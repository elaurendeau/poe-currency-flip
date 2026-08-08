package com.poeflipfinder.backend.framework.divinationcard;

import static org.assertj.core.api.Assertions.assertThat;

import com.poeflipfinder.backend.entity.Currency;
import com.poeflipfinder.backend.entity.DivinationCardReward;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * Loads the real bundled reference-data/divination-card-rewards.json --
 * unlike Item Icons, this file is authored reference data we own (manually
 * captured from the PoE Wiki per docs/DATA_SOURCES.md), not a third-party
 * response subject to drift, so there's no separate "fixture vs real" split
 * to test against.
 */
class BundledDivinationCardReferenceGatewayTest {

    private final BundledDivinationCardReferenceGateway gateway = new BundledDivinationCardReferenceGateway();

    @Test
    void findAll_loadsTheRealBundledCatalogResource_withoutError() {
        List<DivinationCardReward> rewards = gateway.findAll();

        assertThat(rewards).isNotEmpty();
    }

    @Test
    void findAll_resolvesAPredictableCard_withItsFixedCurrencyReward() {
        DivinationCardReward chaoticDisposition = findByName(gateway.findAll(), "Chaotic Disposition");

        assertThat(chaoticDisposition.card().displayName()).isEqualTo("Chaotic Disposition");
        assertThat(chaoticDisposition.card().itemType()).isEqualTo(Currency.ItemType.DIVINATION_CARD);
        assertThat(chaoticDisposition.stackSize()).isEqualTo(1);
        assertThat(chaoticDisposition.rewardCurrency().displayName()).isEqualTo("Chaos Orb");
        assertThat(chaoticDisposition.rewardQuantity()).isEqualTo(5);
        assertThat(chaoticDisposition.isPredictable()).isTrue();
    }

    @Test
    void findAll_keepsANonPredictableCard_visibleButMarkedExcluded() {
        DivinationCardReward theDoctor = findByName(gateway.findAll(), "The Doctor");

        assertThat(theDoctor.isPredictable()).isFalse();
    }

    private DivinationCardReward findByName(List<DivinationCardReward> rewards, String cardName) {
        return rewards.stream()
                .filter(reward -> reward.card().displayName().equals(cardName))
                .findFirst()
                .orElseThrow(() -> new AssertionError("No reward entry for " + cardName));
    }
}
