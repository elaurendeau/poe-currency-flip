package com.poeflipfinder.backend.framework.web.generated.api;

import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.web.context.request.NativeWebRequest;

/**
 * Hand-maintained shim required by the OpenAPI-generated *Api interfaces'
 * default (unimplemented) methods -- the generator expects this class to
 * exist but does not emit it itself when generateSupportingFiles is off
 * (see backend/pom.xml). Lives in src/main, not target/generated-sources,
 * so it survives `mvn clean`. Our real controllers override every generated
 * method, so this only backs the interface's placeholder example responses.
 */
public final class ApiUtil {

    private ApiUtil() {
    }

    public static void setExampleResponse(NativeWebRequest req, String contentType, String example) {
        try {
            HttpServletResponse res = req.getNativeResponse(HttpServletResponse.class);
            res.setCharacterEncoding("UTF-8");
            res.addHeader("Content-Type", contentType);
            res.getWriter().print(example);
        } catch (IOException e) {
            // Placeholder-response writing failure is not actionable; every real
            // endpoint overrides the generated default method that calls this.
        }
    }
}
