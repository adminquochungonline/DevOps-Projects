# CI/CD Stacks (Docker) for DevOps-Project-01

Two **independent** Docker Compose stacks, one per tool. Each lives in its own
folder and can be started/stopped on its own. They share an external Docker
network (`dp01-cicd`).

| Stack | Folder | URL | Default login |
| ----- | ------ | --- | ------------- |
| Jenkins | `jenkins/` | http://localhost:8080 | `admin` / `admin123` |
| SonarQube (+Postgres) | `sonarqube/` | http://localhost:9000 | `admin` / `admin` |

> Change all default passwords before using beyond local development.

**Artifacts:** this project uses **JFrog Cloud (SaaS)** at
`https://trialm744ol.jfrog.io` for the Maven repository, not a local Artifactory.
The self-hosted Artifactory OSS stack was removed because it is too resource
heavy for this machine. The `artifactory/` folder is kept for reference only.

## One-time host setup

```bash
# Shared network used by all three stacks
docker network create dp01-cicd

# SonarQube (Elasticsearch) requires a higher map count
sudo sysctl -w vm.max_map_count=262144
# make it persistent:
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-sonarqube.conf
```

## Start / stop each stack

```bash
# Jenkins
cd jenkins && docker compose up -d --build

# SonarQube
cd ../sonarqube && docker compose up -d
```

Stop a stack with `docker compose down` (keeps data) or `docker compose down -v`
(wipes its volumes).

## Notes

- **SonarQube uses PostgreSQL** for persistence (bundled in its stack).
- First startup of SonarQube takes a few minutes (JVM + database migrations).

## How the pipeline reaches these tools

Jenkins runs as a container on the `dp01-cicd` network:

- SonarQube (local): `http://dp01-sonarqube:9000` — by **container name**, not
  `localhost` (env `SONAR_HOST_URL` in `Jenkinsfile.app`).
- Artifactory (JFrog Cloud SaaS): `https://trialm744ol.jfrog.io/artifactory`
  (in `jenkins/settings.xml` and the app `pom.xml` `distributionManagement`).

## Credentials to create in Jenkins

| ID | Type | For |
| -- | ---- | --- |
| `sonarqube-token` | Secret text | SonarQube analysis token (User > Security > Generate Token) |
| `jfrog-creds` | Username/password | JFrog Cloud user + password/identity token |
| `azure-sp` | Username/password | Azure Service Principal appId/secret |
| `azure-tenant` | Secret text | Azure tenant ID |
| `azure-subscription` | Secret text | Azure subscription ID |
| `tf-db-username` | Secret text | MySQL admin user (you choose) |
| `tf-db-password` | Secret text | MySQL admin password (you choose) |
| `vmss-ssh-pubkey` | Secret text | SSH public key for VMSS |
