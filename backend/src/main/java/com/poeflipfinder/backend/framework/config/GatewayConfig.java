package com.poeflipfinder.backend.framework.config;

import com.poeflipfinder.backend.framework.exchange.GggExchangeSourceGateway;
import com.poeflipfinder.backend.framework.itemicon.GggItemIconGateway;
import com.poeflipfinder.backend.framework.league.GggLeagueGateway;
import com.poeflipfinder.backend.framework.persistence.CurrencyJpaRepository;
import com.poeflipfinder.backend.framework.persistence.ExchangeIngestionStateJpaRepository;
import com.poeflipfinder.backend.framework.persistence.ExchangeMarketSnapshotJpaRepository;
import com.poeflipfinder.backend.framework.persistence.JpaCurrencyReferenceGateway;
import com.poeflipfinder.backend.framework.persistence.JpaLeagueReferenceGateway;
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

    // www.pathofexile.com (unlike api.pathofexile.com and web.poecdn.com) sits
    // behind bot protection that 403s requests without a descriptive User-Agent
    // -- confirmed live: GggItemIconGateway's default Java client User-Agent
    // was rejected calling from Render's IP range, though it worked from a
    // residential IP during local testing. Applied to every GGG RestClient
    // via this customizer rather than per-gateway, since it's a standing
    // requirement for talking to any pathofexile.com/poecdn.com endpoint.
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
    public GggItemIconGateway gggItemIconGateway(RestClient.Builder restClientBuilder) {
        return new GggItemIconGateway(restClientBuilder);
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

    // Testability seam for the ingestion interactor's first-run lookback
    // calculation -- system clock in production, fixed in tests.
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
