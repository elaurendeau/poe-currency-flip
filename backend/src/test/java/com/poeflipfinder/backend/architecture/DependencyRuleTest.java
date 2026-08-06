package com.poeflipfinder.backend.architecture;

import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.syntax.ArchRuleDefinition;

/**
 * Mechanically enforces the Dependency Rule from docs/CODE_STYLE.md §
 * "Clean Architecture / Layering (the Onion, with names)": entities and use
 * cases must stay framework-free so the rule is a build failure, not prose
 * nobody checks.
 */
@AnalyzeClasses(packages = "com.poeflipfinder.backend")
class DependencyRuleTest {

    @ArchTest
    static final ArchRule entitiesAndUseCasesStayFrameworkFree =
            ArchRuleDefinition.noClasses()
                    .that()
                    .resideInAnyPackage(
                            "com.poeflipfinder.backend.entity..", "com.poeflipfinder.backend.usecase..")
                    .should()
                    .dependOnClassesThat()
                    .resideInAnyPackage(
                            "org.springframework..", "jakarta.persistence..", "java.net.http..")
                    .because(
                            "entities and use cases must have zero Spring/JPA/HTTP-client"
                                    + " dependencies -- see docs/CODE_STYLE.md § Clean Architecture");
}
