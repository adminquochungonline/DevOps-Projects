# Runtime image for sample-app (DevOps-Project-06)
FROM eclipse-temurin:8-jre-alpine

WORKDIR /app

# The pipeline runs 'mvn clean package -DskipTests' first,
# so the image packages the exact compiled JAR artifact.
COPY target/demo-workshop-*.jar sample_app.jar

EXPOSE 8000

ENTRYPOINT ["java", "-jar", "sample_app.jar"]
