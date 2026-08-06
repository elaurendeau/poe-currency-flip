package com.poeflipfinder.backend.framework.config;

import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

/**
 * Regression test: www.pathofexile.com 403'd every request from Render's IP
 * range because the default Java HTTP client sends no distinguishing
 * User-Agent -- api.pathofexile.com and web.poecdn.com didn't block it, but
 * confirmed live against production that www.pathofexile.com does. The fix
 * must actually reach outgoing requests, not just exist as an unused bean.
 */
class GatewayConfigTest {

    @Test
    void gggUserAgentCustomizer_attachesDescriptiveUserAgent_toEveryOutgoingRequest() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        new GatewayConfig().gggUserAgentCustomizer().customize(builder);
        RestClient client = builder.build();

        server.expect(requestTo("/ping"))
                .andExpect(header(
                        HttpHeaders.USER_AGENT,
                        "poe-currency-flip/0.1 (+https://github.com/elaurendeau/poe-currency-flip)"))
                .andRespond(withSuccess());

        client.get().uri("/ping").retrieve().toBodilessEntity();

        server.verify();
    }
}
