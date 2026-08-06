package com.poeflipfinder.backend.framework.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Allows the frontend origin to call this API cross-origin -- the frontend
 * (Vercel) and backend (Render) are always different origins in production,
 * and the Vite dev server is a different origin from the backend locally too.
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final String frontendOrigin;

    public WebConfig(@Value("${app.frontend-origin}") String frontendOrigin) {
        this.frontendOrigin = frontendOrigin;
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowedOrigins(frontendOrigin)
                .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH");
    }
}
