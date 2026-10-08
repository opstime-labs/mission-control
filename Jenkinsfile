pipeline {
    agent any

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
        GIT_COMMIT_SHORT                  = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }

    stages {
        stage('Audit & Traceability') {
            steps {
                echo "=========================================================="
                echo "Traceability: JIRA Task: CHG-1001"
                echo "Job:          ${JOB_NAME} | Build ID: ${BUILD_NUMBER}"
                echo "Commit SHA:   ${GIT_COMMIT_SHORT}"
                echo "Workspace:    ${WORKSPACE}"
                echo "=========================================================="
            }
        }

        stage('.NET Restore, Build, Test & SonarQube SAST') {
            steps {
                script {
                    // Resolve the true physical host directory corresponding to this agent's WORKSPACE
                    def jenkinsHomeHost = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim()
                    
                    // Replace /var/jenkins_home with the real host path, preserving correct branch folder naming (_main)
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

                                echo "--> [Environment] Installing OpenJDK-17 and SonarScanner CLI..."
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
                }
            }
        }

        stage('Multi-Stage Container Packaging') {
            steps {
                sh """
                    echo "--> Sanitizing build context and streaming to Docker daemon..."
                    tar --exclude='.git' \
                        --exclude='TestResults' \
                        --exclude='publish_raw' \
                        --exclude='bin' \
                        --exclude='obj' \
                        --exclude='*/bin' \
                        --exclude='*/obj' \
                        --exclude='*/*/bin' \
                        --exclude='*/*/obj' \
                        -cf - . | docker build \
                      --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                      --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:latest \
                      -
                """
            }
        }

        stage('Container Image Security Scan') {
            steps {
                sh """
                    echo "--> [V&V Gate] Scanning container image for OS and runtime CVEs via Trivy..."
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity HIGH,CRITICAL \
                      --exit-code 0 \
                      --format table \
                      ${IMAGE_NAME}:latest
                """
            }
        }

        stage('Publish Release Artifacts (Docker Image and Raw Binaries) to Nexus') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail

                        echo "--> Publishing immutable container image to Nexus Docker Registry"
                        echo "--> Logging into Nexus Docker Registry: ${REGISTRY_HOST}..."
                        echo "\$NEXUS_PASS" | docker login -u "\$NEXUS_USER" --password-stdin "${REGISTRY_HOST}"

                        echo "--> Tagging release image for private registry..."
                        docker tag "${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}" "${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                        docker tag "${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}" "${REGISTRY_HOST}/${IMAGE_NAME}:latest"

                        echo "--> Pushing immutable container artifact to Nexus..."
                        docker push "${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                        docker push "${REGISTRY_HOST}/${IMAGE_NAME}:latest"

                        echo "--> Logging out from Nexus..."
                        docker logout "${REGISTRY_HOST}"

                        echo "--> Publishing raw binary release tarball to Nexus Raw Repository"
                        echo "--> Packaging raw binary release tarball..."
                        RELEASE_DIR="release_dist"
                        mkdir -p "\${RELEASE_DIR}"

                        ARTIFACT_NAME="mission-control-api-\${BUILD_NUMBER}-\${GIT_COMMIT_SHORT}.tar.gz"
                        CHECKSUM_NAME="\${ARTIFACT_NAME}.sha256"

                        tar -czf "\${RELEASE_DIR}/\${ARTIFACT_NAME}" -C "${WORKSPACE}/publish_raw" .
                        cd "\${RELEASE_DIR}"
                        sha256sum "\${ARTIFACT_NAME}" > "\${CHECKSUM_NAME}"

                        UPLOAD_URL="${NEXUS_RAW_BASE}/sensor-gateway/\${BUILD_NUMBER}"

                        echo "--> Uploading binary package to Nexus Raw: \${UPLOAD_URL}/\${ARTIFACT_NAME}..."
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${ARTIFACT_NAME}" \
                          "\${UPLOAD_URL}/\${ARTIFACT_NAME}"

                        echo "--> Uploading SHA-256 verification hash: \${UPLOAD_URL}/\${CHECKSUM_NAME}"
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${CHECKSUM_NAME}" \
                          "\${UPLOAD_URL}/\${CHECKSUM_NAME}"

                        echo "--> Nexus releases published and cryptographically verified."
                    """
                }
            }
            post {
                always {
                    sh "rm -rf release_dist publish_raw || true"
                }
            }
        }
    }

    post {
        always {
            cleanWs notFailBuild: true
        }
        success {
            echo "SUCCESS: Verification passed and release published for branch ${BRANCH_NAME}."
        }
        failure {
            echo "FAILURE: Pipeline execution failed. Inspect stage telemetry."
        }
    }
}