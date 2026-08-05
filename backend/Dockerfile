# Reference Dockerfile for the Spring Boot backend, assuming the standard
# Spring Initializr Maven layout (pom.xml, mvnw, src/) once the project is
# scaffolded. See docs/DEPLOYMENT.md for the packaging/deployment rationale.

# --- Build stage ---
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
RUN ./mvnw -q -DskipTests dependency:go-offline
COPY src ./src
RUN ./mvnw -q -DskipTests package

# --- Run stage ---
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
