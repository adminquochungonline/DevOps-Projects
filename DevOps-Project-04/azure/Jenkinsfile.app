// Application pipeline for DevOps-Project-04 (Django on Azure Container Apps).
// Validates the app, analyzes it in SonarQube, builds the image inside ACR and
// deploys a new container app revision with Terraform.
//
// Flow: checks & tests -> code quality -> image build (ACR) -> [approval]
//       -> terraform apply (container app revision) -> smoke test.
//
// Assumes the platform already exists (run Jenkinsfile.infra first).
//
// Uses the DevOps-Project-01 CI/CD environment:
//   * dp01/jenkins image (Terraform 1.9.8, Azure CLI, Docker CLI)
//   * SonarQube at http://dp01-sonarqube:9000 on the dp01-cicd network
//   * Terraform state in the same Azure Storage account, key django-app/terraform.tfstate
// Python is NOT installed in the Jenkins image, so Python steps run in
// throwaway containers that share the Jenkins workspace volume
// (--volumes-from dp01-jenkins), the same trick used for the Sonar scanner.
//
// Required Jenkins credentials:
//   azure-sp           (Username with password)  -> Service Principal appId/password
//   azure-tenant       (Secret text)             -> Azure tenant ID
//   azure-subscription (Secret text)             -> Azure subscription ID
//   sonarqube-token    (Secret text)             -> SonarQube analysis token
//   django-secret-key  (Secret text)             -> Django SECRET_KEY (NEW for this project)

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 45, unit: 'MINUTES')
    }

    parameters {
        booleanParam(
            name: 'RUN_SONAR',
            defaultValue: true,
            description: 'Run the SonarQube code-quality analysis.'
        )
        booleanParam(
            name: 'DEPLOY',
            defaultValue: false,
            description: 'Deploy the new image as a container app revision (requires approval).'
        )
        string(
            name: 'ENVIRONMENT',
            defaultValue: 'dev',
            description: 'Target environment. MUST match the value used in Jenkinsfile.infra.'
        )
        string(
            name: 'LOCATION',
            defaultValue: 'southeastasia',
            description: 'Azure region. MUST match Jenkinsfile.infra.'
        )
        string(
            name: 'NAME_SUFFIX',
            defaultValue: 'dp04hung',
            description: 'Registry suffix. MUST match Jenkinsfile.infra (registry = "<ENVIRONMENT>django<NAME_SUFFIX>").'
        )
        string(
            name: 'ALERT_EMAIL',
            defaultValue: '',
            description: 'MUST match Jenkinsfile.infra, otherwise this apply removes/recreates the alert rules.'
        )
        string(
            name: 'CICD_PRINCIPAL_ID',
            defaultValue: '',
            description: 'MUST match Jenkinsfile.infra, otherwise this apply removes the AcrPush assignment.'
        )
        booleanParam(
            name: 'MANAGE_ACR_PULL_ASSIGNMENT',
            defaultValue: false,
            description: 'MUST match Jenkinsfile.infra. true makes Terraform own the AcrPull assignment (needs roleAssignments/write); false leaves it to a manual grant.'
        )
        string(
            name: 'IMAGE_TAG',
            defaultValue: '',
            description: 'Image tag. Empty = "<BUILD_NUMBER>-<short git sha>". Never use "latest" (Terraform rejects it).'
        )
        string(
            name: 'ALLOWED_HOSTS',
            defaultValue: '*',
            description: 'Django ALLOWED_HOSTS. Narrow to the ingress FQDN after the first deploy.'
        )
        string(
            name: 'TFSTATE_STORAGE_ACCOUNT',
            defaultValue: 'hddevopsprojectstg001',
            description: 'Azure Storage account holding the Terraform remote state.'
        )
    }

    environment {
        // Paths relative to the repo root; this project lives in a subfolder.
        APP_DIR   = 'DevOps-Project-04'
        INFRA_DIR = 'DevOps-Project-04/azure/terraform'

        // Self-hosted CI tools from DevOps-Project-01, reachable by container
        // name on the shared 'dp01-cicd' Docker network.
        SONAR_HOST_URL = 'http://dp01-sonarqube:9000'
        JENKINS_CONTAINER = 'dp01-jenkins'
        CICD_NETWORK = 'dp01-cicd'

        PYTHON_IMAGE = 'python:3.12-slim'
        SONAR_SCANNER_IMAGE = 'sonarsource/sonar-scanner-cli:latest'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def sha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    // Fall back to the declared defaults: on the first build after a
                    // parameter is added, Jenkins has not registered it yet and
                    // params.X is null.
                    def envName = (params.ENVIRONMENT ?: 'dev').trim()
                    def suffix = (params.NAME_SUFFIX ?: 'dp04hung').trim()
                    env.RESOLVED_IMAGE_TAG = params.IMAGE_TAG?.trim() ? params.IMAGE_TAG.trim() : "${env.BUILD_NUMBER}-${sha}"
                    env.REGISTRY_NAME = "${envName}django${suffix}"
                    env.IMAGE_REF = "${env.REGISTRY_NAME}.azurecr.io/django-app:${env.RESOLVED_IMAGE_TAG}"
                    echo "Image to build: ${env.IMAGE_REF}"
                }
                sh 'terraform version && az version --output table || true'
            }
        }

        stage('Django Checks & Tests') {
            steps {
                // The workspace lives in the jenkins_home volume, so the helper
                // container mounts it with --volumes-from instead of -v.
                // Work happens on a copy in /tmp so the checkout stays clean.
                sh '''
                    docker run --rm \
                      --volumes-from ${JENKINS_CONTAINER} \
                      -w "${WORKSPACE}/${APP_DIR}" \
                      -e DJANGO_SETTINGS_MODULE=hello_world_django_app.settings_azure \
                      -e DJANGO_SECRET_KEY=ci-checks-only-not-a-deployment-secret-000000 \
                      -e DJANGO_SECURE_SSL_REDIRECT=false \
                      ${PYTHON_IMAGE} \
                      sh -c '
                        set -e
                        cp -r . /tmp/app && cd /tmp/app
                        cp azure/app/settings_azure.py azure/app/urls_azure.py hello_world_django_app/
                        pip install --quiet --no-cache-dir -r azure/app/requirements.txt
                        python manage.py check --deploy
                        python manage.py test --verbosity 2
                      '
                '''
            }
        }

        stage('Code Quality (SonarQube)') {
            when { expression { return params.RUN_SONAR } }
            steps {
                withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                    sh '''
                        docker run --rm \
                          --network ${CICD_NETWORK} \
                          --volumes-from ${JENKINS_CONTAINER} \
                          -w "${WORKSPACE}/${APP_DIR}" \
                          -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
                          -e SONAR_TOKEN="${SONAR_TOKEN}" \
                          ${SONAR_SCANNER_IMAGE} \
                          -Dsonar.projectKey=devops-project-04 \
                          -Dsonar.projectName=devops-project-04 \
                          -Dsonar.sources=. \
                          -Dsonar.python.version=3.12 \
                          -Dsonar.exclusions=**/staticfiles/**,**/__pycache__/**,**/*.sqlite3,**/.terraform/**
                    '''
                }
            }
        }

        stage('Build Image (ACR)') {
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZ_CLIENT_ID', passwordVariable: 'AZ_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID'),
                    string(credentialsId: 'azure-subscription', variable: 'AZ_SUBSCRIPTION_ID')
                ]) {
                    // Built by ACR Tasks, not by the local daemon: no registry
                    // login, no image push from Jenkins, no privileged docker build.
                    sh '''
                        set -e
                        az login --service-principal \
                          -u "${AZ_CLIENT_ID}" -p "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" >/dev/null
                        az account set --subscription "${AZ_SUBSCRIPTION_ID}"

                        cd "${WORKSPACE}/${APP_DIR}"
                        az acr build \
                          --registry "${REGISTRY_NAME}" \
                          --image "django-app:${RESOLVED_IMAGE_TAG}" \
                          --file azure/app/Dockerfile \
                          .
                    '''
                }
            }
        }

        stage('Preflight: AcrPull') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZ_CLIENT_ID', passwordVariable: 'AZ_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID'),
                    string(credentialsId: 'azure-subscription', variable: 'AZ_SUBSCRIPTION_ID')
                ]) {
                    // Without AcrPull the revision fails minutes later inside an
                    // Azure polling error. Check it here and say exactly what to fix.
                    sh '''
                        set -e
                        az login --service-principal \
                          -u "${AZ_CLIENT_ID}" -p "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" >/dev/null
                        az account set --subscription "${AZ_SUBSCRIPTION_ID}"

                        ENV_NAME="${ENVIRONMENT:-dev}"
                        RG="${ENV_NAME}-django-app-rg"
                        IDENTITY="${ENV_NAME}-django-app-identity"

                        ACR_ID=$(az acr show -n "${REGISTRY_NAME}" --query id -o tsv)
                        PRINCIPAL_ID=$(az identity show -g "${RG}" -n "${IDENTITY}" --query principalId -o tsv)
                        echo "registry:  ${REGISTRY_NAME}"
                        echo "identity:  ${IDENTITY} (principal ${PRINCIPAL_ID})"

                        if az role assignment list --scope "${ACR_ID}" --include-inherited \
                             --query "[?roleDefinitionName=='AcrPull'].principalId" -o tsv \
                           | grep -qx "${PRINCIPAL_ID}"; then
                            echo "AcrPull present."
                            exit 0
                        fi

                        echo "ERROR: the container app identity has no AcrPull on the registry," >&2
                        echo "so Container Apps cannot pull the image. Grant it with an account" >&2
                        echo "holding Owner or User Access Administrator, then wait 2-5 minutes" >&2
                        echo "for RBAC to propagate and re-run this job:" >&2
                        echo >&2
                        echo "  az role assignment create \\" >&2
                        echo "    --assignee-object-id ${PRINCIPAL_ID} \\" >&2
                        echo "    --assignee-principal-type ServicePrincipal \\" >&2
                        echo "    --role AcrPull \\" >&2
                        echo "    --scope ${ACR_ID}" >&2
                        echo >&2
                        echo "Or set MANAGE_ACR_PULL_ASSIGNMENT=true in both jobs to let Terraform" >&2
                        echo "own the assignment (needs roleAssignments/write on the pipeline SP)." >&2
                        exit 1
                    '''
                }
            }
        }

        stage('Approval to Deploy') {
            when { expression { return params.DEPLOY } }
            steps {
                script {
                    timeout(time: 30, unit: 'MINUTES') {
                        input(
                            message: "Deploy ${env.IMAGE_REF} to the '${params.ENVIRONMENT}' container app?",
                            ok: 'Yes, deploy'
                        )
                    }
                }
            }
        }

        stage('Deploy Revision (Terraform)') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'ARM_CLIENT_ID', passwordVariable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'azure-subscription', variable: 'ARM_SUBSCRIPTION_ID'),
                    string(credentialsId: 'django-secret-key', variable: 'TF_VAR_django_secret_key')
                ]) {
                    dir("${INFRA_DIR}") {
                        // Same Terraform config and state as the infra pipeline;
                        // the only difference is container_image, which turns the
                        // container app on and pins the revision to this image.
                        sh '''
                            set -e
                            # Defaults via ${VAR:-...} so a build triggered before
                            # Jenkins picked up a newly added parameter still gets a
                            # valid value. An empty allowed_hosts would make Django
                            # reject every request with DisallowedHost.
                            ENV_NAME="${ENVIRONMENT:-dev}"
                            export TF_VAR_environment="${ENV_NAME}"
                            export TF_VAR_location="${LOCATION:-southeastasia}"
                            export TF_VAR_name_suffix="${NAME_SUFFIX:-dp04hung}"
                            export TF_VAR_alert_email="${ALERT_EMAIL:-}"
                            export TF_VAR_cicd_principal_id="${CICD_PRINCIPAL_ID:-}"
                            export TF_VAR_manage_acr_pull_assignment="${MANAGE_ACR_PULL_ASSIGNMENT:-false}"
                            export TF_VAR_container_image="${IMAGE_REF}"
                            export TF_VAR_allowed_hosts="${ALLOWED_HOSTS:-*}"

                            rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
                            terraform init -input=false -reconfigure \
                              -backend-config="storage_account_name=${TFSTATE_STORAGE_ACCOUNT}"

                            # Self-heal an orphan: if a previous run created the
                            # container app in Azure but failed while polling (for
                            # example the revision could not pull its image), the
                            # resource exists without being in state and every later
                            # apply fails with "already exists". Import it instead.
                            ADDR='module.container_app[0].azurerm_container_app.main'
                            RG="${ENV_NAME}-django-app-rg"
                            APP="${ENV_NAME}-django-app"
                            if ! terraform state list | grep -qxF "${ADDR}"; then
                                az login --service-principal \
                                  -u "${ARM_CLIENT_ID}" -p "${ARM_CLIENT_SECRET}" --tenant "${ARM_TENANT_ID}" >/dev/null
                                az account set --subscription "${ARM_SUBSCRIPTION_ID}"
                                APP_ID=$(az containerapp show -g "${RG}" -n "${APP}" --query id -o tsv 2>/dev/null || true)
                                if [ -n "${APP_ID}" ]; then
                                    echo "Container app exists in Azure but not in state; importing before plan."
                                    terraform import "${ADDR}" "${APP_ID}"
                                fi
                            fi

                            terraform plan -input=false -out=tfplan
                            terraform apply -input=false -auto-approve tfplan
                            echo "=== Outputs ==="
                            terraform output
                            # Persist the URL so the smoke test does not need
                            # backend credentials to read state again.
                            terraform output -raw app_url > "${WORKSPACE}/app_url.txt"
                        '''
                    }
                }
            }
        }

        stage('Smoke Test') {
            when { expression { return params.DEPLOY } }
            steps {
                sh '''
                    APP_URL=$(cat "${WORKSPACE}/app_url.txt" 2>/dev/null || echo "")
                    if [ -z "${APP_URL}" ]; then
                        echo "No app_url recorded by the deploy stage; skipping smoke test."
                        exit 0
                    fi
                    echo "Smoke testing ${APP_URL}/health/"
                    for i in $(seq 1 10); do
                        code=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/health/" || echo "000")
                        echo "attempt ${i}: HTTP ${code}"
                        if [ "${code}" = "200" ]; then
                            echo "Smoke test passed: ${APP_URL}"
                            exit 0
                        fi
                        sleep 15
                    done
                    echo "Smoke test failed. Inspect logs:"
                    echo "  az containerapp logs show -g ${ENVIRONMENT}-django-app-rg -n ${ENVIRONMENT}-django-app --tail 100"
                    exit 1
                '''
            }
        }
    }

    post {
        success {
            echo "Application pipeline completed for '${params.ENVIRONMENT}' (image ${env.IMAGE_REF})."
        }
        failure {
            echo 'Application pipeline failed. Check the stage logs above.'
        }
        always {
            cleanWs()
        }
    }
}
