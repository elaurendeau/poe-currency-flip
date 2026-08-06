# Build context must be the repo root (not backend/), since pom.xml's
# openapi-generator config reads ../contracts/openapi.yaml -- the contract
# lives outside this directory. See docker-compose.yml for the invocation.

# --- Build stage ---
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY backend/mvnw .
COPY backend/.mvn .mvn
COPY backend/pom.xml .
RUN ./mvnw -q -DskipTests dependency:go-offline
COPY contracts /contracts
COPY backend/src ./src
RUN ./mvnw -q -DskipTests package

# --- Run stage ---
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
