# Jenkins Server (local, Docker) for DevOps-Project-01

A ready-to-use Jenkins controller running in Docker, with the CI/CD tooling for
this project pre-installed: **JDK 11 + Maven** (to build the Spring Boot app),
**Terraform** (for `infrastructure-azure/`), **Azure CLI**, and the **Docker
CLI** (using the host's Docker daemon).

> This setup is intended for **local learning/testing**. See the security notes
> before exposing it anywhere.

## Contents

| File | Purpose |
| ---- | ------- |
| `Dockerfile` | Jenkins LTS (JDK 17) image + JDK 11, Maven, Terraform, Azure CLI, Docker CLI |
| `plugins.txt` | Jenkins plugins baked into the image |
| `docker-compose.yml` | Runs Jenkins with ports, volumes and Docker socket |
| `init.groovy.d/01-create-admin.groovy` | Seeds an admin user on first boot |

## Prerequisites

- Docker and Docker Compose installed (verified: Docker 29.x, Compose v5.x).
- Ports `8080` and `50000` free on the host.

## Quick Start

From this `jenkins/` directory:

```bash
# Build the image and start Jenkins in the background
docker compose up -d --build

# Watch startup logs (first boot installs plugins, takes a minute or two)
docker compose logs -f jenkins
```

When you see `Jenkins is fully up and running`, open:

- URL: http://localhost:8080
- Username: `admin`
- Password: `admin123`

The setup wizard is disabled; the admin user is created automatically from the
`JENKINS_ADMIN_ID` / `JENKINS_ADMIN_PASSWORD` variables in `docker-compose.yml`.
**Change these before doing anything beyond local use.**

### Managing the server

```bash
docker compose stop        # stop (keeps data)
docker compose start       # start again
docker compose down        # remove container (data persists in volume)
docker compose down -v     # remove container AND all Jenkins data
```

Jenkins data lives in the named volume `jenkins_home`, so jobs, config and
credentials survive `docker compose down`.

## Verify the tooling inside the container

```bash
docker compose exec jenkins bash -lc '
  java -version
  mvn -version
  terraform version
  az version
  docker version --format "{{.Client.Version}}"
'
```

JDK 11 for builds is at `/opt/java/jdk-11` (Jenkins itself runs on the base
image's JDK 17). Set `JAVA_HOME=/opt/java/jdk-11` in the pipeline for Maven.

> Note: this Docker-based setup is optional. If you instead run Jenkins natively
> on the host (installed via apt, systemd service), Jenkins runs on JDK 21 and
> JDK 11 for builds lives at `/usr/lib/jvm/java-11-openjdk-amd64`. The
> `Jenkinsfile.app` uses that native path.

## Credentials to add in Jenkins

Before running the pipeline (added later as a `Jenkinsfile`), create these under
**Manage Jenkins → Credentials → System → Global**:

| ID (suggested) | Type | Used for |
| -------------- | ---- | -------- |
| `azure-sp` | Microsoft Azure Service Principal (or Username/Password) | `terraform`/`az` login |
| `sonarcloud-token` | Secret text | SonarCloud analysis (`SONAR_TOKEN`) |
| `jfrog-creds` | Username with password | Maven deploy to JFrog Artifactory |
| `tf-db-username` | Secret text | Terraform `db_username` |
| `tf-db-password` | Secret text | Terraform `db_password` |
| `vmss-ssh-pubkey` | Secret text (or file) | Terraform `admin_ssh_public_key` |

> Do NOT hardcode these in the repo. Note that `Java-Login-App/settings.xml`
> currently contains plaintext JFrog credentials — rotate them and switch to a
> Jenkins-managed `settings.xml` (Config File Provider plugin) or credentials
> binding.

## Recommended plugins (already included)

`workflow-aggregator`, `pipeline-stage-view`, `git`, `github`,
`credentials-binding`, `config-file-provider`, `sonar`, `blueocean` and more —
see `plugins.txt`. Add others via **Manage Jenkins → Plugins**.

## Pipelines

There are **two separate pipelines** at the project root:

- [`../Jenkinsfile.infra`](../Jenkinsfile.infra) — **Infrastructure**. Terraform
  `plan → approval → apply` (or `destroy`) for `infrastructure-azure`. No app
  build/deploy.
- [`../Jenkinsfile.app`](../Jenkinsfile.app) — **Application**. Build & test
  (Maven/JDK 11) → SonarCloud → publish WAR to JFrog → approval → deploy to the
  VM Scale Set → smoke test. Assumes the infrastructure already exists.

Both use `settings.xml` in this folder for Maven, which reads JFrog credentials
from environment variables (no secrets in the file).

### Typical order

1. Run the **infra** pipeline with `TF_ACTION=apply` to create Azure resources.
2. Run the **app** pipeline with `DEPLOY=true` to build and roll out the app.

### Create the jobs

For each pipeline, create a job:

1. Add all credentials from the table above (**Manage Jenkins → Credentials**).
2. **New Item → Pipeline**.
3. Pipeline → *Pipeline script from SCM* → Git → this repo, Script Path
   `DevOps-Project-01/Jenkinsfile.infra` (or `.app`).
4. Save and **Build with Parameters**.

### Infra pipeline parameters

| Parameter | Purpose |
| --------- | ------- |
| `TF_ACTION` | `plan-only`, `apply`, or `destroy`. `apply`/`destroy` pause for **approval**. |
| `ENVIRONMENT` | Terraform `environment` prefix (e.g. `dev`). |
| `LOCATION` | Azure region (default `southeastasia`). |

### App pipeline parameters

| Parameter | Purpose |
| --------- | ------- |
| `RUN_SONAR` | Run SonarCloud analysis. |
| `PUBLISH_ARTIFACT` | Publish the WAR to JFrog. |
| `DEPLOY` | Deploy to the VM Scale Set (requires **approval**). |
| `ENVIRONMENT` | Matches the infrastructure name prefix (e.g. `dev`). |

## Security notes

- Default admin credentials are for local use only — change them.
- Mounting `/var/run/docker.sock` gives the Jenkins container control over the
  host Docker daemon (effectively host-level access). Acceptable for local
  experimentation; in production use a separate, isolated build agent.
- To use the Docker CLI from inside Jenkins, the container joins the host's
  `docker` group via `group_add` in `docker-compose.yml`. That value must match
  the GID of `/var/run/docker.sock` on your host (currently `984`). If Docker
  commands fail with "permission denied", update it:
  `stat -c '%g' /var/run/docker.sock` and set `group_add` to that number.
- Do not expose port 8080 to untrusted networks with the default settings.
