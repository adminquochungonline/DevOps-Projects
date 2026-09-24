// Application pipeline for DevOps-Project-01 (Java Login App).
// Builds, tests, analyzes and publishes the app, then deploys to the existing
// Azure VM Scale Set. Assumes the infrastructure already exists (provision it
// first with Jenkinsfile.infra).
//
// Flow: build & test -> code quality -> publish artifact -> [approval] -> deploy -> smoke test.
//
// Required Jenkins credentials:
//   sonarcloud-token  (Secret text)             -> SonarCloud token
//   jfrog-creds       (Username with password)  -> JFrog Artifactory
//   azure-sp          (Username with password)  -> Service Principal appId/password
//   azure-tenant      (Secret text)             -> Azure tenant ID

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
            description: 'Run the SonarCloud code-quality analysis.'
        )
        booleanParam(
            name: 'PUBLISH_ARTIFACT',
            defaultValue: true,
            description: 'Publish the built WAR to JFrog Artifactory.'
        )
        booleanParam(
            name: 'DEPLOY',
            defaultValue: false,
            description: 'Deploy to the Azure VM Scale Set (requires approval).'
        )
        string(
            name: 'ENVIRONMENT',
            defaultValue: 'dev',
            description: 'Target environment (matches the infrastructure name prefix).'
        )
    }

    environment {
        // Build with JDK 11. In the Docker-based Jenkins (dp01/jenkins image)
        // JDK 11 lives at /opt/java/jdk-11.
        JAVA_HOME = '/opt/java/jdk-11'
        PATH      = "/opt/java/jdk-11/bin:${env.PATH}"

        APP_DIR   = 'Java-Login-App'
        INFRA_DIR = 'infrastructure-azure'

        // Local self-hosted CI tools (reachable by container name on the shared
        // 'dp01-cicd' Docker network). Override in the job if you use SaaS.
        SONAR_HOST_URL = 'http://dp01-sonarqube:9000'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'java -version && mvn -version'
            }
        }

        stage('Build & Test') {
            steps {
                dir("${APP_DIR}") {
                    sh 'mvn -B clean verify'
                }
            }
            post {
                always {
                    junit testResults: "${APP_DIR}/target/surefire-reports/*.xml", allowEmptyResults: true
                    archiveArtifacts artifacts: "${APP_DIR}/target/*.war", fingerprint: true, allowEmptyArchive: true
                }
            }
        }

        stage('Code Quality (SonarCloud)') {
            when { expression { return params.RUN_SONAR } }
            steps {
                withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                    dir("${APP_DIR}") {
                        sh '''
                            mvn -B sonar:sonar \
                              -Dsonar.host.url=${SONAR_HOST_URL} \
                              -Dsonar.token=${SONAR_TOKEN}
                        '''
                    }
                }
            }
        }

        stage('Publish Artifact (JFrog)') {
            when { expression { return params.PUBLISH_ARTIFACT } }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'jfrog-creds',
                    usernameVariable: 'JFROG_USERNAME',
                    passwordVariable: 'JFROG_PASSWORD'
                )]) {
                    dir("${APP_DIR}") {
                        // Uses the env-var based settings.xml in cicd/jenkins/ (no secrets in file)
                        sh 'mvn -B -s ../cicd/jenkins/settings.xml deploy -DskipTests'
                    }
                }
            }
        }

        stage('Approval to Deploy') {
            when { expression { return params.DEPLOY } }
            steps {
                script {
                    timeout(time: 30, unit: 'MINUTES') {
                        input(
                            message: "Deploy the application to the '${params.ENVIRONMENT}' VM Scale Set?",
                            ok: 'Yes, deploy'
                        )
                    }
                }
            }
        }

        stage('Deploy to VM Scale Set') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZ_CLIENT_ID', passwordVariable: 'AZ_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID')
                ]) {
                    sh '''
                        az login --service-principal \
                          -u "${AZ_CLIENT_ID}" -p "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" >/dev/null

                        RG="${ENVIRONMENT}-java-app-rg"
                        VMSS="${ENVIRONMENT}-vmss"

                        echo "Rolling out latest application to ${VMSS} in ${RG}..."
                        az vmss update-instances \
                          --resource-group "${RG}" \
                          --name "${VMSS}" \
                          --instance-ids "*"
                    '''
                }
            }
        }

        stage('Smoke Test') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp', usernameVariable: 'AZ_CLIENT_ID', passwordVariable: 'AZ_CLIENT_SECRET'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID')
                ]) {
                    sh '''
                        az login --service-principal \
                          -u "${AZ_CLIENT_ID}" -p "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" >/dev/null

                        RG="${ENVIRONMENT}-java-app-rg"
                        APPGW="${ENVIRONMENT}-appgw-pip"

                        APP_IP=$(az network public-ip show \
                          --resource-group "${RG}" --name "${APPGW}" \
                          --query ipAddress -o tsv 2>/dev/null || echo "")

                        if [ -z "${APP_IP}" ]; then
                            echo "Could not resolve Application Gateway public IP; skipping smoke test."
                            exit 0
                        fi
                        echo "Application Gateway public IP: ${APP_IP}"
                        for i in $(seq 1 10); do
                            code=$(curl -s -o /dev/null -w "%{http_code}" "http://${APP_IP}/" || echo "000")
                            echo "attempt ${i}: HTTP ${code}"
                            if [ "${code}" = "200" ] || [ "${code}" = "302" ]; then
                                echo "Smoke test passed."; exit 0
                            fi
                            sleep 15
                        done
                        echo "Smoke test did not get a healthy response in time."; exit 1
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Application pipeline completed for '${params.ENVIRONMENT}'."
        }
        failure {
            echo 'Application pipeline failed. Check the stage logs above.'
        }
        always {
            cleanWs()
        }
    }
}
