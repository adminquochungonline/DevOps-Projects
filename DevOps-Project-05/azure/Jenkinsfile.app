// Application pipeline for DevOps-Project-05 (regapp on AKS).
// Builds and tests the WAR, analyzes it in SonarQube, builds the image inside
// ACR and rolls it out to AKS with the manifests in azure/k8s/.
//
// Flow: maven build & test -> [sonar] -> image build (ACR) -> preflight
//       -> [approval] -> kubectl apply + rollout (auto-undo on failure) -> smoke test.
//
// Assumes the platform already exists (run azure/Jenkinsfile.infra first).
// Resource names are derived by convention (same as azure/terraform/main.tf),
// so this job never reads or writes Terraform state.
//
// Uses the DevOps-Project-01 CI/CD environment:
//   * dp01/jenkins image (JDK 11, Maven, Azure CLI). kubectl is NOT in the
//     image: the deploy stage downloads the version matching the cluster
//     (checksum-verified) and caches it under $JENKINS_HOME/tools/kubectl.
//   * SonarQube at http://dp01-sonarqube:9000 on the dp01-cicd network
//
// Required Jenkins credentials:
//   azure-sp           (Username with password)  -> Service Principal appId/password
//   azure-tenant       (Secret text)             -> Azure tenant ID
//   azure-subscription (Secret text)             -> Azure subscription ID
//   sonarqube-token    (Secret text)             -> only when RUN_SONAR = true
//
// Job: "Pipeline script from SCM", Script Path: DevOps-Project-05/azure/Jenkinsfile.app

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
            description: 'Run the SonarQube analysis (project key devops-project-05).'
        )
        booleanParam(
            name: 'DEPLOY',
            defaultValue: true,
            description: 'Roll the new image out to AKS (pauses for approval). false = build and push only.'
        )
        string(
            name: 'ENVIRONMENT',
            defaultValue: 'dev',
            description: 'Target environment. MUST match Jenkinsfile.infra.'
        )
        string(
            name: 'NAME_SUFFIX',
            defaultValue: 'dp05hung',
            description: 'MUST match Jenkinsfile.infra (registry = "<ENVIRONMENT>regapp<NAME_SUFFIX>").'
        )
        string(
            name: 'IMAGE_TAG',
            defaultValue: '',
            description: 'Image tag. Empty = "<BUILD_NUMBER>-<short git sha>". "latest" is rejected.'
        )
    }

    environment {
        // The app targets Java 1.7 bytecode: JDK 11 still compiles it, JDK 21 does not.
        JAVA_HOME = '/opt/java/jdk-11'
        PATH      = "/opt/java/jdk-11/bin:${env.PATH}"

        // Paths relative to the repo root; this project lives in a subfolder.
        PROJECT_DIR = 'DevOps-Project-05'
        APP_DIR     = 'DevOps-Project-05/hello-world'
        K8S_DIR     = 'DevOps-Project-05/azure/k8s'

        K8S_NAMESPACE  = 'regapp'
        SONAR_HOST_URL = 'http://dp01-sonarqube:9000'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def sha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    // Fall back to the declared defaults: on the first build after a
                    // parameter is added, Jenkins has not registered it yet.
                    def envName = (params.ENVIRONMENT ?: 'dev').trim()
                    def suffix  = (params.NAME_SUFFIX ?: 'dp05hung').trim()
                    def tag     = params.IMAGE_TAG?.trim() ? params.IMAGE_TAG.trim() : "${env.BUILD_NUMBER}-${sha}"
                    if (tag == 'latest') {
                        error('IMAGE_TAG "latest" is not allowed: use a unique tag so rollouts are traceable.')
                    }

                    // Naming convention from azure/terraform/main.tf
                    env.RESOLVED_IMAGE_TAG = tag
                    env.REGISTRY_NAME      = "${envName}regapp${suffix}"
                    env.RESOURCE_GROUP     = "${envName}-regapp-rg"
                    env.AKS_NAME           = "${envName}-regapp-aks"
                    env.IMAGE_REF          = "${env.REGISTRY_NAME}.azurecr.io/regapp:${tag}"
                    echo "Image to build: ${env.IMAGE_REF}"
                    echo "Target cluster: ${env.AKS_NAME} (${env.RESOURCE_GROUP})"
                }
                sh 'java -version && mvn -version && az version --output table || true'
            }
        }

        stage('Build & Test (Maven)') {
            steps {
                dir("${APP_DIR}") {
                    sh 'mvn -B clean verify'
                }
            }
            post {
                always {
                    junit testResults: "${APP_DIR}/**/target/surefire-reports/*.xml", allowEmptyResults: true
                    archiveArtifacts artifacts: "${APP_DIR}/webapp/target/webapp.war", fingerprint: true, allowEmptyArchive: true
                }
            }
        }

        stage('Code Quality (SonarQube)') {
            when { expression { return params.RUN_SONAR } }
            steps {
                withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                    dir("${APP_DIR}") {
                        // The scanner needs Java 17+, so it runs on the Jenkins
                        // JDK 21 while the code is still analyzed as JDK 11.
                        withEnv(['JAVA_HOME=/opt/java/openjdk', 'PATH+JDK21=/opt/java/openjdk/bin']) {
                            sh '''
                                mvn -B org.sonarsource.scanner.maven:sonar-maven-plugin:3.11.0.3922:sonar \
                                  -Dsonar.host.url=${SONAR_HOST_URL} \
                                  -Dsonar.token=${SONAR_TOKEN} \
                                  -Dsonar.projectKey=devops-project-05 \
                                  -Dsonar.projectName=devops-project-05 \
                                  -Dsonar.java.jdkHome=/opt/java/jdk-11
                            '''
                        }
                    }
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
                    // Built by ACR Tasks: no registry password, no push from the
                    // Jenkins host. The context is DevOps-Project-05/ and
                    // .dockerignore limits the upload to the Dockerfile + WAR.
                    sh '''
                        set -e
                        # Per-build Azure CLI profile: removed by cleanWs(), and not
                        # shared with other jobs running on this controller.
                        export AZURE_CONFIG_DIR="${WORKSPACE}/.azure"
                        az login --service-principal \
                          -u "${AZ_CLIENT_ID}" -p "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" >/dev/null
                        az account set --subscription "${AZ_SUBSCRIPTION_ID}"

                        if ! az acr show -n "${REGISTRY_NAME}" --query id -o tsv >/dev/null 2>&1; then
                            echo "ERROR: registry ${REGISTRY_NAME} not found. Run dp05-azure-infra (TF_ACTION=apply)" >&2
                            echo "with the same ENVIRONMENT / NAME_SUFFIX first." >&2
                            exit 1
                        fi

                        cd "${WORKSPACE}/${PROJECT_DIR}"
                        az acr build \
                          --registry "${REGISTRY_NAME}" \
                          --image "regapp:${RESOLVED_IMAGE_TAG}" \
                          --file docker/Dockerfile \
                          .
                    '''
                }
            }
        }

        stage('Preflight: AKS + AcrPull') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZ_CLIENT_ID', passwordVariable: 'AZ_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID'),
                    string(credentialsId: 'azure-subscription', variable: 'AZ_SUBSCRIPTION_ID')
                ]) {
                    // Without AcrPull the pods sit in ImagePullBackOff and the
                    // rollout only times out minutes later. Check it up front.
                    sh '''
                        set -e
                        export AZURE_CONFIG_DIR="${WORKSPACE}/.azure"
                        az account set --subscription "${AZ_SUBSCRIPTION_ID}"

                        STATE=$(az aks show -g "${RESOURCE_GROUP}" -n "${AKS_NAME}" --query provisioningState -o tsv 2>/dev/null || true)
                        if [ "${STATE}" != "Succeeded" ]; then
                            echo "ERROR: AKS cluster ${AKS_NAME} is '${STATE:-missing}'. Run dp05-azure-infra (TF_ACTION=apply) first." >&2
                            exit 1
                        fi

                        ACR_ID=$(az acr show -n "${REGISTRY_NAME}" --query id -o tsv)
                        KUBELET_ID=$(az aks show -g "${RESOURCE_GROUP}" -n "${AKS_NAME}" \
                          --query identityProfile.kubeletidentity.objectId -o tsv)
                        echo "kubelet identity: ${KUBELET_ID}"

                        if az role assignment list --scope "${ACR_ID}" --include-inherited \
                             --query "[?roleDefinitionName=='AcrPull'].principalId" -o tsv \
                           | grep -qx "${KUBELET_ID}"; then
                            echo "AcrPull present."
                            exit 0
                        fi

                        echo "ERROR: the AKS kubelet identity has no AcrPull on ${REGISTRY_NAME}." >&2
                        echo "Either re-run dp05-azure-infra with MANAGE_ACR_PULL_ASSIGNMENT=true, or grant it" >&2
                        echo "with an Owner / User Access Administrator account, wait 2-5 minutes, re-run:" >&2
                        echo >&2
                        echo "  az role assignment create --assignee-object-id ${KUBELET_ID} --assignee-principal-type ServicePrincipal --role AcrPull --scope ${ACR_ID}" >&2
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
                            message: "Deploy ${env.IMAGE_REF} to AKS '${env.AKS_NAME}'?",
                            ok: 'Yes, deploy'
                        )
                    }
                }
            }
        }

        stage('Deploy to AKS') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZ_CLIENT_ID', passwordVariable: 'AZ_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID'),
                    string(credentialsId: 'azure-subscription', variable: 'AZ_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        set -e
                        export AZURE_CONFIG_DIR="${WORKSPACE}/.azure"
                        # Kubeconfig inside the workspace (deleted by cleanWs), never ~/.kube.
                        export KUBECONFIG="${WORKSPACE}/.kube/config"
                        az account set --subscription "${AZ_SUBSCRIPTION_ID}"

                        # --- kubectl matching the cluster minor version (cached) ---
                        MINOR=$(az aks show -g "${RESOURCE_GROUP}" -n "${AKS_NAME}" \
                          --query currentKubernetesVersion -o tsv | cut -d. -f1,2)
                        KVER=$(curl -fsSL "https://dl.k8s.io/release/stable-${MINOR}.txt")
                        case "$(uname -m)" in
                            x86_64)  ARCH=amd64 ;;
                            aarch64) ARCH=arm64 ;;
                            *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
                        esac
                        BIN_DIR="${JENKINS_HOME}/tools/kubectl/${KVER}-${ARCH}"
                        if [ ! -x "${BIN_DIR}/kubectl" ]; then
                            echo "Downloading kubectl ${KVER} (${ARCH})"
                            mkdir -p "${BIN_DIR}"
                            URL="https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
                            curl -fsSL -o "${BIN_DIR}/kubectl.tmp" "${URL}"
                            echo "$(curl -fsSL "${URL}.sha256")  ${BIN_DIR}/kubectl.tmp" | sha256sum -c -
                            chmod +x "${BIN_DIR}/kubectl.tmp"
                            mv "${BIN_DIR}/kubectl.tmp" "${BIN_DIR}/kubectl"
                        fi
                        export PATH="${BIN_DIR}:${PATH}"
                        kubectl version --client

                        # --- cluster credentials (local account, no kubelogin needed) ---
                        az aks get-credentials -g "${RESOURCE_GROUP}" -n "${AKS_NAME}" \
                          --file "${KUBECONFIG}" --overwrite-existing
                        kubectl get nodes -o wide

                        # --- render and apply manifests ---
                        RENDER_DIR="${WORKSPACE}/.k8s-rendered"
                        rm -rf "${RENDER_DIR}" && mkdir -p "${RENDER_DIR}"
                        cp "${WORKSPACE}/${K8S_DIR}"/*.yaml "${RENDER_DIR}/"
                        sed -i "s#__IMAGE__#${IMAGE_REF}#g" "${RENDER_DIR}/deployment.yaml"
                        grep -n "image:" "${RENDER_DIR}/deployment.yaml"

                        # Namespace first: kubectl applies a directory alphabetically.
                        kubectl apply -f "${RENDER_DIR}/namespace.yaml"
                        kubectl apply -f "${RENDER_DIR}/deployment.yaml" -f "${RENDER_DIR}/service.yaml"
                        kubectl -n "${K8S_NAMESPACE}" annotate deployment/regapp \
                          kubernetes.io/change-cause="jenkins ${JOB_NAME} #${BUILD_NUMBER}: ${IMAGE_REF}" --overwrite

                        if ! kubectl -n "${K8S_NAMESPACE}" rollout status deployment/regapp --timeout=5m; then
                            echo "Rollout failed. Diagnostics:" >&2
                            kubectl -n "${K8S_NAMESPACE}" get pods -o wide || true
                            kubectl -n "${K8S_NAMESPACE}" get events --sort-by=.lastTimestamp | tail -30 || true
                            echo "Rolling back to the previous revision (no-op on the first deploy)." >&2
                            kubectl -n "${K8S_NAMESPACE}" rollout undo deployment/regapp || true
                            exit 1
                        fi
                        kubectl -n "${K8S_NAMESPACE}" rollout history deployment/regapp | tail -5

                        # --- wait for the Azure Load Balancer public IP ---
                        IP=""
                        for i in $(seq 1 30); do
                            IP=$(kubectl -n "${K8S_NAMESPACE}" get svc regapp \
                              -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
                            [ -n "${IP}" ] && break
                            echo "waiting for load balancer IP (${i}/30)"
                            sleep 10
                        done
                        if [ -z "${IP}" ]; then
                            echo "ERROR: service regapp has no external IP after 5 minutes." >&2
                            kubectl -n "${K8S_NAMESPACE}" describe svc regapp >&2 || true
                            exit 1
                        fi
                        # Persist the URL so the smoke test needs no cluster access.
                        echo "http://${IP}/webapp/" > "${WORKSPACE}/app_url.txt"
                        echo "App URL: http://${IP}/webapp/"
                    '''
                }
            }
        }

        stage('Smoke Test') {
            when { expression { return params.DEPLOY } }
            steps {
                sh '''
                    APP_URL=$(cat "${WORKSPACE}/app_url.txt")
                    echo "Smoke testing ${APP_URL}"
                    for i in $(seq 1 12); do
                        body=$(curl -s --max-time 10 "${APP_URL}" || true)
                        if echo "${body}" | grep -q "New user Register"; then
                            echo "Smoke test passed: ${APP_URL}"
                            exit 0
                        fi
                        echo "attempt ${i}: not ready yet"
                        sleep 10
                    done
                    echo "Smoke test failed. Inspect with:"
                    echo "  az aks get-credentials -g ${RESOURCE_GROUP} -n ${AKS_NAME}"
                    echo "  kubectl -n ${K8S_NAMESPACE} get pods,svc; kubectl -n ${K8S_NAMESPACE} logs deploy/regapp --tail 100"
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
            // Also removes the per-build Azure CLI profile and kubeconfig.
            cleanWs()
        }
    }
}
