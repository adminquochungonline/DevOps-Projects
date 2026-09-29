# Runtime image for the "regapp" Java web app (DevOps-Project-05).
# Shared by both pipelines: Jenkinsfile.local (local Docker) and
# azure/Jenkinsfile.app (ACR + AKS).
#
# Build context: DevOps-Project-05/ (see ../.dockerignore). Maven builds the WAR
# in the pipeline first, so the image ships exactly the artifact that passed
# the tests:
#   docker build -f docker/Dockerfile -t regapp:dev .
#
# Differences from ../hello-world/Dockerfile (the tutorial version, unchanged):
#   * pinned Tomcat 9 instead of tomcat:latest. Tomcat 9 keeps the javax.servlet
#     namespace that web.xml 2.5 / servlet-api 2.5 in this app are written for;
#     Tomcat 10+ moved to jakarta.*.
#   * webapps.dist (manager, host-manager, examples) is NOT copied into webapps:
#     those admin/sample apps are not needed to serve the WAR.
#   * runs as a non-root user.
FROM tomcat:9.0.122-jre21-temurin-noble

# Container-aware heap sizing: follow the memory limit set by docker/Kubernetes.
ENV CATALINA_OPTS="-XX:MaxRAMPercentage=75.0"

RUN groupadd --system --gid 10001 tomcat \
    && useradd --system --uid 10001 --gid tomcat \
         --home-dir /usr/local/tomcat --shell /usr/sbin/nologin tomcat \
    && rm -rf /usr/local/tomcat/webapps/* \
    && chown -R tomcat:tomcat \
         /usr/local/tomcat/webapps /usr/local/tomcat/work \
         /usr/local/tomcat/temp /usr/local/tomcat/logs

# Served under /webapp/, same URL as in the README.
COPY --chown=tomcat:tomcat hello-world/webapp/target/webapp.war /usr/local/tomcat/webapps/webapp.war

# Numeric UID so Kubernetes runAsNonRoot can verify it.
USER 10001

EXPOSE 8080
CMD ["catalina.sh", "run"]
