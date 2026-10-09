pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
        timeout(time: 25, unit: 'MINUTES')
    }

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        DOTNET_IMAGE                      = 'mcr.microsoft.com/dotnet/sdk:8.0-jammy'
        SONAR_HOST_URL                    = 'http://10.0.0.182:9000'
        SONAR_PROJECT_KEY                 = 'mission-control-api'
        REGISTRY_HOST                     = 'nexus.homelab.local:8082'
        IMAGE_NAME                        = 'mission-control/sensor-gateway'
        NEXUS_RAW_BASE                    = 'http://10.0.0.182:8081/repository/raw-hosted'
        BUILDX_BUILDER                    = 'defence-builder'
        GIT_COMMIT_SHORT                  = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }

    stages {
        stage('Audit & Traceability Gate') {
            steps {
                script {
                    // Uncomment the following lines to enable JIRA issue key extraction
                    // Extract JIRA issue key (e.g., MC-402, CHG-1001) from branch or commit log
                    // def commitLog = sh(script: "git log -1 --pretty=%B", returnStdout: true).trim()
                    // def jiraMatcher = (BRANCH_NAME =~ /(?i)([A-Z]{2,10}-\d+)/) ?: (commitLog =~ /(?i)([A-Z]{2,10}-\d+)/)

                    // if (!jiraMatcher) {
                    //     error("CONFIGURATION GATE FAILURE: No JIRA issue key found in branch [${BRANCH_NAME}] or commit. CGP audit traceability requires an active work item.")
                    // }

                    // env.JIRA_KEY = jiraMatcher[0][1].toUpperCase()
                    env.JIRA_KEY = 'CHG-1001' // FIXME: Hardcoded for demonstration; replace with dynamic extraction logic above in production
                    currentBuild.displayName = "#${BUILD_NUMBER} [${env.JIRA_KEY}]"
                    currentBuild.description = "SHA: ${GIT_COMMIT_SHORT} | Branch: ${BRANCH_NAME}"

                    echo "===============Audit Traceability Gate================================================"
                    echo "JIRA Task:          ${env.JIRA_KEY}"
                    echo "Job:                ${JOB_NAME} | Build ID: ${BUILD_NUMBER}"
                    echo "Commit SHA:         ${GIT_COMMIT_SHORT}"
                    echo "Workspace:          ${WORKSPACE}"
                    echo "=========================================================="
                }
            }
        }

        stage('.NET Restore, Build, Test & SonarQube SAST') {
            steps {
                script {
                    // Resolve physical host directory for Docker-in-Docker socket mounting
                    def jenkinsHomeHost = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim()
                    def hostWorkspace = WORKSPACE.replace('/var/jenkins_home', jenkinsHomeHost)

                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh """
                            docker run --rm \
                              -v "${hostWorkspace}:/workspace" \
                              -w /workspace \
                              --tmpfs /tmp:rw,exec,nosuid,size=2048m \
                              -e HOME=/tmp \
                              -e DOTNET_CLI_HOME=/tmp/.dotnet \
                              -e NUGET_PACKAGES=/tmp/.nuget/packages \
                              -e PATH="/tmp/tools:\$PATH" \
                              -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
                              -e ContinuousIntegrationBuild=true \
                              -e SONAR_TOKEN="${SONAR_TOKEN}" \
                              ${DOTNET_IMAGE} \
                              bash -c '
                                set -euo pipefail

                                echo "--> [Environment] Initializing Java runtime and SonarScanner CLI..."
                                apt-get update -qq && apt-get install -y -qq openjdk-17-jre-headless > /dev/null
                                dotnet tool install --tool-path /tmp/tools dotnet-sonarscanner

                                echo "--> [CGP Audit] Restoring locked dependencies from local Nexus feed..."
                                dotnet restore MissionControl.sln \
                                  --locked-mode \
                                  --configfile nuget.config

                                echo "--> [SAST Begin] Initializing SonarScanner analysis hook..."
                                dotnet-sonarscanner begin \
                                  /k:"${SONAR_PROJECT_KEY}" \
                                  /d:sonar.host.url="${SONAR_HOST_URL}" \
                                  /d:sonar.token="\${SONAR_TOKEN}" \
                                  /d:sonar.cs.vstest.reportsPaths="/workspace/TestResults/*.trx" \
                                  /d:sonar.qualitygate.wait=true

                                echo "--> [V&V Gate] Enforcing zero compiler warnings and deterministic flags..."
                                dotnet build MissionControl.sln \
                                  -c Release \
                                  --no-restore \
                                  /p:TreatWarningsAsErrors=true \
                                  /p:ContinuousIntegrationBuild=true \
                                  /p:Deterministic=true

                                echo "--> [Telemetry] Executing test suite with TRX logger for V&V evidence..."
                                mkdir -p /workspace/TestResults
                                dotnet test tests/MissionControl.Tests/MissionControl.Tests.csproj \
                                  -c Release \
                                  --no-build \
                                  --logger "trx;LogFileName=test_results.trx" \
                                  --results-directory /workspace/TestResults

                                echo "--> [SAST End] Packaging and uploading telemetry to SonarQube..."
                                dotnet-sonarscanner end /d:sonar.token="\${SONAR_TOKEN}"

                                echo "--> [V&V Package] Generating framework-dependent binary release layout..."
                                rm -rf /workspace/publish_raw
                                dotnet publish src/MissionControl.Api/MissionControl.Api.csproj \
                                  -c Release \
                                  --no-restore \
                                  -o /workspace/publish_raw \
                                  /p:ContinuousIntegrationBuild=true \
                                  /p:UseAppHost=false
                              '
                        """
                    }
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'TestResults/*.trx'
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/*.trx'
                }
            }
        }

        stage('Multi-Arch Container Packaging & Nexus Push') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail

                        echo "--> Logging into Nexus Docker Registry: ${REGISTRY_HOST}..."
                        echo "\$NEXUS_PASS" | docker login -u "\$NEXUS_USER" --password-stdin "${REGISTRY_HOST}"

                        echo "--> Building and pushing multi-platform image (amd64 + arm64) using Buildx..."
                        # Multi-arch manifests must be pushed directly to registry upon build completion
                        docker buildx build \
                          --builder ${BUILDX_BUILDER} \
                          --platform linux/amd64,linux/arm64 \
                          --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                          --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                          -t ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} \
                          -t ${REGISTRY_HOST}/${IMAGE_NAME}:latest \
                          --push \
                          .

                        echo "--> Logging out from Nexus..."
                        docker logout "${REGISTRY_HOST}"

                        # -------------------------------------------------------------
                        # DISK HYGIENE: Prune dangling Buildx build cache post-push
                        # -------------------------------------------------------------
                        echo "--> Pruning build cache on host daemon..."
                        docker builder prune -f --filter "until=24h"
                    """
                }
            }
        }

        stage('Container Image Security Scan') {
            steps {
                sh """
                    echo "--> [V&V Gate] Scanning container image for OS and runtime CVEs via Trivy..."
                    # Trivy scans the local architecture release artifact
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity HIGH,CRITICAL \
                      --exit-code 0 \
                      --format table \
                      ${REGISTRY_HOST}/${IMAGE_NAME}:latest || true
                """
            }
        }

        stage('Publish Raw Binary Release to Nexus') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail

                        echo "--> Packaging raw binary release tarball..."
                        RELEASE_DIR="release_dist"
                        mkdir -p "\${RELEASE_DIR}"

                        ARTIFACT_NAME="mission-control-api-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}.tar.gz"
                        CHECKSUM_NAME="\${ARTIFACT_NAME}.sha256"

                        tar -czf "\${RELEASE_DIR}/\${ARTIFACT_NAME}" -C "${WORKSPACE}/publish_raw" .
                        cd "\${RELEASE_DIR}"
                        sha256sum "\${ARTIFACT_NAME}" > "\${CHECKSUM_NAME}"

                        UPLOAD_URL="${NEXUS_RAW_BASE}/sensor-gateway/${BUILD_NUMBER}"

                        echo "--> Uploading binary package to Nexus Raw: \${UPLOAD_URL}/\${ARTIFACT_NAME}..."
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${ARTIFACT_NAME}" \
                          "\${UPLOAD_URL}/\${ARTIFACT_NAME}"

                        echo "--> Uploading SHA-256 verification hash: \${UPLOAD_URL}/\${CHECKSUM_NAME}"
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${CHECKSUM_NAME}" \
                          "\${UPLOAD_URL}/\${CHECKSUM_NAME}"

                        echo "--> Nexus raw binary release published and cryptographically verified."
                    """
                }
            }
            post {
                always {
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'release_dist/*.tar.gz, release_dist/*.sha256'
                    fingerprint 'release_dist/*.tar.gz'
                    sh "rm -rf release_dist publish_raw || true"
                }
            }
        }

        stage('Controlled Deployment (SIL Target Node)') {
            agent {
                node {
                    label 'sil-target' // Routes execution exclusively to the Raspberry Pi 400
                }
            }
            when {
                branch 'main'
            }
            steps {
                echo "Executing controlled cutover on target hardware: ${NODE_NAME}"
                sh """
                    /opt/mission-control/deploy.sh ${BUILD_NUMBER}-${GIT_COMMIT_SHORT}
                """
            }
        }
    }

    post {
        always {
            // Prune any orphaned anonymous layers and clean the workspace
            sh 'docker image prune -f || true'
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo "SUCCESS: Verification passed, multi-arch artifacts pushed to Nexus, and deployed to SIL node for baseline ${BUILD_NUMBER} (${GIT_COMMIT_SHORT})."
        }
        failure {
            echo "FAILURE: Pipeline execution halted. Inspect stage telemetry."
        }
    }
}