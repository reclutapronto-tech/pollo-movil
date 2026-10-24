FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./pom.xml
COPY src ./src
RUN mvn -B -ntp -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/target/quarkus-app/lib/ ./quarkus-app/lib/
COPY --from=build /workspace/target/quarkus-app/*.jar ./quarkus-app/
COPY --from=build /workspace/target/quarkus-app/app/ ./quarkus-app/app/
COPY --from=build /workspace/target/quarkus-app/quarkus/ ./quarkus-app/quarkus/
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "quarkus-app/quarkus-run.jar"]
