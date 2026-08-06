package com.poeflipfinder.backend.framework.config;

import com.poeflipfinder.backend.framework.league.GggLeagueGateway;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

/** Wires Gateway implementations as singleton beans; they hold no per-request state. */
@Configuration
public class GatewayConfig {

    @Bean
    public GggLeagueGateway gggLeagueGateway(RestClient.Builder restClientBuilder) {
        return new GggLeagueGateway(restClientBuilder);
    }
}
