package com.poeflipfinder.backend.framework.config;

import com.poeflipfinder.backend.framework.exchange.GggExchangeSourceGateway;
import com.poeflipfinder.backend.framework.itemicon.GggItemIconGateway;
import com.poeflipfinder.backend.framework.league.GggLeagueGateway;
import com.poeflipfinder.backend.framework.persistence.CurrencyJpaRepository;
import com.poeflipfinder.backend.framework.persistence.ExchangeIngestionStateJpaRepository;
import com.poeflipfinder.backend.framework.persistence.ExchangeMarketSnapshotJpaRepository;
import com.poeflipfinder.backend.framework.persistence.JpaCurrencyReferenceGateway;
import com.poeflipfinder.backend.framework.persistence.JpaLeagueReferenceGateway;
import com.poeflipfinder.backend.framework.persistence.JpaSnapshotQueryGateway;
import com.poeflipfinder.backend.framework.persistence.JpaSnapshotRepositoryGateway;
import com.poeflipfinder.backend.framework.persistence.LeagueJpaRepository;
import com.poeflipfinder.backend.gateway.ItemIconGateway;
import java.time.Clock;
import org.springframework.boot.web.client.RestClientCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.web.client.RestClient;

/** Wires Gateway implementations as singleton beans; they hold no per-request state. */
@Configuration
public class GatewayConfig {

    // Standard API-citizenship practice for the remaining live GGG calls
    // (League List, Currency Exchange) -- identifies the app so GGG can
    // reach out if it ever causes trouble. NOT a fix for any specific
    // block: confirmed live 2026-08-06 that GggItemIconGateway's 403 was
    // unrelated to User-Agent content (any non-empty value works) -- see
    // GggItemIconGateway's docstring for why that gateway no longer makes
    // a live call at all.
    @Bean
    public RestClientCustomizer gggUserAgentCustomizer() {
        return builder -> builder.defaultHeader(
                HttpHeaders.USER_AGENT, "poe-currency-flip/0.1 (+https://github.com/elaurendeau/poe-currency-flip)");
    }

    @Bean
    public GggLeagueGateway gggLeagueGateway(RestClient.Builder restClientBuilder) {
        return new GggLeagueGateway(restClientBuilder);
    }

    @Bean
    public GggExchangeSourceGateway gggExchangeSourceGateway(RestClient.Builder restClientBuilder) {
        return new GggExchangeSourceGateway(restClientBuilder);
    }

    @Bean
    public GggItemIconGateway gggItemIconGateway() {
        return new GggItemIconGateway();
    }

    @Bean
    public JpaCurrencyReferenceGateway jpaCurrencyReferenceGateway(
            CurrencyJpaRepository currencyJpaRepository, ItemIconGateway itemIconGateway) {
        return new JpaCurrencyReferenceGateway(currencyJpaRepository, itemIconGateway);
    }

    @Bean
    public JpaLeagueReferenceGateway jpaLeagueReferenceGateway(LeagueJpaRepository leagueJpaRepository) {
        return new JpaLeagueReferenceGateway(leagueJpaRepository);
    }

    @Bean
    public JpaSnapshotRepositoryGateway jpaSnapshotRepositoryGateway(
            ExchangeIngestionStateJpaRepository ingestionStateJpaRepository,
            ExchangeMarketSnapshotJpaRepository snapshotJpaRepository,
            Clock clock) {
        return new JpaSnapshotRepositoryGateway(ingestionStateJpaRepository, snapshotJpaRepository, clock);
    }

    @Bean
    public JpaSnapshotQueryGateway jpaSnapshotQueryGateway(
            LeagueJpaRepository leagueJpaRepository,
            CurrencyJpaRepository currencyJpaRepository,
            ExchangeMarketSnapshotJpaRepository snapshotJpaRepository,
            ExchangeIngestionStateJpaRepository ingestionStateJpaRepository) {
        return new JpaSnapshotQueryGateway(
                leagueJpaRepository, currencyJpaRepository, snapshotJpaRepository, ingestionStateJpaRepository);
    }

    // Testability seam for the ingestion interactor's first-run lookback
    // calculation -- system clock in production, fixed in tests.
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
