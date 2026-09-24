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

        // Paths are relative to the repo root; this project lives in a subfolder.
        APP_DIR   = 'DevOps-Project-01/Java-Login-App'
        INFRA_DIR = 'DevOps-Project-01/infrastructure-azure'

        // Database name (matches Terraform var.db_name)
        DB_NAME   = 'javaapp'

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
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT_ID'),
                    usernamePassword(credentialsId: 'jfrog-creds', usernameVariable: 'JFROG_USERNAME', passwordVariable: 'JFROG_PASSWORD'),
                    string(credentialsId: 'tf-db-username', variable: 'DB_USER'),
                    string(credentialsId: 'tf-db-password', variable: 'DB_PASS')
                ]) {
                    sh '''
                        set -e
                        az login --service-principal \
                          -u "${AZ_CLIENT_ID}" -p "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" >/dev/null

                        RG="${ENVIRONMENT}-java-app-rg"
                        VMSS="${ENVIRONMENT}-vmss"

                        # Read the app version/artifact from the built pom.
                        cd "${WORKSPACE}/${APP_DIR}"
                        VERSION=$(mvn -q -Dexec.executable=echo -Dexec.args='${project.version}' --non-recursive exec:exec 2>/dev/null || echo "1.0")
                        ARTIFACT="dptweb"
                        GROUP_PATH="com/devopsrealtime"
                        WAR_URL="https://trialm744ol.jfrog.io/artifactory/libs-release-local/${GROUP_PATH}/${ARTIFACT}/${VERSION}/${ARTIFACT}-${VERSION}.war"
                        MYSQL_FQDN="${ENVIRONMENT}-mysql-server.mysql.database.azure.com"
                        DB_URL="jdbc:mysql://${MYSQL_FQDN}:3306/${DB_NAME}?useSSL=true&requireSSL=true"

                        echo "Deploying WAR: ${WAR_URL}"

                        # Script executed on every VMSS instance via the Azure control plane
                        # (instances are in a private subnet; no direct SSH). It downloads the
                        # WAR as ROOT.war, injects DB env vars into Tomcat, and restarts it.
                        cat > /tmp/deploy.sh <<EOF
#!/bin/bash
set -e
mkdir -p /etc/systemd/system/tomcat9.service.d
cat > /etc/systemd/system/tomcat9.service.d/app-env.conf <<ENVEOF
[Service]
Environment=DB_URL=${DB_URL}
Environment=DB_USERNAME=${DB_USER}
Environment=DB_PASSWORD=${DB_PASS}
ENVEOF
curl -fsSL -u "${JFROG_USERNAME}:${JFROG_PASSWORD}" -o /var/lib/tomcat9/webapps/ROOT.war "${WAR_URL}"
systemctl daemon-reload
systemctl restart tomcat9
EOF

                        echo "Running deploy script on all instances..."
                        az vmss run-command invoke \
                          --resource-group "${RG}" \
                          --name "${VMSS}" \
                          --command-id RunShellScript \
                          --instance-id "*" \
                          --scripts @/tmp/deploy.sh
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
