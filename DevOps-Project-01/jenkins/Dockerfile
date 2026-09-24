# Jenkins controller for DevOps-Project-01 with CI/CD tooling pre-installed.
# Base: official Jenkins LTS (runs on JDK 17). Build tools for the Java app
# (JDK 11 + Maven), Terraform, Azure CLI and Docker CLI are added on top.
FROM jenkins/jenkins:lts-jdk17

# Switch to root to install OS packages
USER root

ARG TERRAFORM_VERSION=1.9.8
ARG MAVEN_VERSION=3.9.9
# Eclipse Temurin JDK 11 (Debian 13/Trixie no longer ships openjdk-11 in apt)
ARG TEMURIN11_URL=https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.25%2B9/OpenJDK11U-jdk_x64_linux_hotspot_11.0.25_9.tar.gz

# Base utilities
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        unzip \
        git \
    && rm -rf /var/lib/apt/lists/*

# JDK 11 (for building the Spring Boot app) via Eclipse Temurin.
# Jenkins itself keeps running on the base image's JDK 17; builds target JDK 11
# via JAVA_HOME=/opt/java/jdk-11 in the pipeline.
RUN mkdir -p /opt/java \
    && curl -fsSL -o /tmp/jdk11.tar.gz "${TEMURIN11_URL}" \
    && tar -xzf /tmp/jdk11.tar.gz -C /opt/java \
    && mv /opt/java/jdk-11* /opt/java/jdk-11 \
    && rm /tmp/jdk11.tar.gz \
    && /opt/java/jdk-11/bin/java -version

# Maven (Apache binary distribution)
RUN curl -fsSL -o /tmp/maven.tar.gz \
        "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    && tar -xzf /tmp/maven.tar.gz -C /opt \
    && ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven \
    && ln -s /opt/maven/bin/mvn /usr/local/bin/mvn \
    && rm /tmp/maven.tar.gz \
    && mvn -version

# Terraform (pinned version, matches infrastructure-azure tooling)
RUN curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && terraform version

# Azure CLI (official Microsoft install script)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && az version

# Docker CLI only (the daemon is provided by the host via the mounted socket)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Pre-install commonly used Jenkins plugins so first startup is ready to go.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Skip the setup wizard; admin user is seeded via docker-compose env + init.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

USER jenkins
