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
                    env.RESOLVED_IMAGE_TAG = params.IMAGE_TAG?.trim() ? params.IMAGE_TAG.trim() : "${env.BUILD_NUMBER}-${sha}"
                    env.REGISTRY_NAME = "${params.ENVIRONMENT}django${params.NAME_SUFFIX}"
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
                            export TF_VAR_environment=${ENVIRONMENT}
                            export TF_VAR_location=${LOCATION}
                            export TF_VAR_name_suffix=${NAME_SUFFIX}
                            export TF_VAR_alert_email=${ALERT_EMAIL}
                            export TF_VAR_cicd_principal_id=${CICD_PRINCIPAL_ID}
                            export TF_VAR_manage_acr_pull_assignment=${MANAGE_ACR_PULL_ASSIGNMENT}
                            export TF_VAR_container_image=${IMAGE_REF}
                            export TF_VAR_allowed_hosts=${ALLOWED_HOSTS}

                            rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
                            terraform init -input=false -reconfigure \
                              -backend-config="storage_account_name=${TFSTATE_STORAGE_ACCOUNT}"
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
