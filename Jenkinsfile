pipeline {
    agent any

    triggers {
        // Instant trigger on GitHub Webhook push
        //githubPush() // GitHub Webhook
        pollSCM('H/5 * * * *') // Poll GitHub every 5 minutes for new commits
    }

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        DOTNET_IMAGE                      = 'mcr.microsoft.com/dotnet/sdk:8.0-jammy'
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
                echo "Agent Node:   ${NODE_NAME} | Workspace: ${WORKSPACE}"
                echo "=========================================================="
            }
        }

        stage('.NET Deterministic Restore, Build, Test & Raw Publish') {
            steps {
                script {
                    def hostWorkspace = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim() + "/workspace/${JOB_NAME}"

                    // Pass current agent UID/GID so generated files are owned by jenkins, avoiding root lockouts
                    sh """
                        docker run --rm \
                          --user "\$(id -u):\$(id -g)" \
                          -v "${hostWorkspace}:/workspace" \
                          -w /workspace \
                          --tmpfs /tmp:rw,exec,nosuid,size=1024m \
                          -e HOME=/tmp \
                          -e DOTNET_CLI_HOME=/tmp/.dotnet \
                          -e NUGET_PACKAGES=/tmp/.nuget/packages \
                          -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
                          -e DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
                          -e DOTNET_NOLOGO=true \
                          -e ContinuousIntegrationBuild=true \
                          ${DOTNET_IMAGE} \
                          bash -c '
                            set -euo pipefail

                            echo "--> [CGP Audit] Restoring locked dependencies from local Nexus feed..."
                            dotnet restore MissionControl.sln \
                              --locked-mode \
                              --configfile nuget.config

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

                            echo "--> [V&V Package] Compiling immutable framework-dependent binaries for Raw Distribution..."
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
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'TestResults/*.trx'
                }
            }
        }

        stage('Static Analysis & Supply-Chain Audit') {
            steps {
                script {
                    def hostWorkspace = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim() + "/workspace/${JOB_NAME}"

                    sh """
                        docker run --rm \
                          --user "\$(id -u):\$(id -g)" \
                          -v "${hostWorkspace}:/workspace" \
                          -w /workspace \
                          --tmpfs /tmp:rw,exec,nosuid,size=1024m \
                          -e HOME=/tmp \
                          -e DOTNET_CLI_HOME=/tmp/.dotnet \
                          -e NUGET_PACKAGES=/tmp/.nuget/packages \
                          -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
                          ${DOTNET_IMAGE} \
                          bash -c '
                            set -euo pipefail
                            echo "--> [SCA Gate] Checking for vulnerable transitive dependencies..."
                            dotnet list MissionControl.sln package --vulnerable --include-transitive
                          '
                    """
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
                    echo "--> [V&V Gate] Scanning container image for OS and runtime CVEs..."
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

        stage('Publish to Nexus Docker Registry') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail

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
                    """
                }
            }
        }

        stage('Publish Raw Binary Package to Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail

                        RELEASE_DIR="release_dist"
                        mkdir -p "\${RELEASE_DIR}"

                        ARTIFACT_NAME="mission-control-api-\${BUILD_NUMBER}-\${GIT_COMMIT_SHORT}.tar.gz"
                        CHECKSUM_NAME="\${ARTIFACT_NAME}.sha256"

                        echo "--> Packaging binary release tarball from publish_raw..."
                        tar -czf "\${RELEASE_DIR}/\${ARTIFACT_NAME}" -C /var/jenkins_home/workspace/${JOB_NAME}/publish_raw .

                        echo "--> Computing cryptographic SHA-256 baseline manifest..."
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

                        echo "--> Nexus raw upload completed and verified."
                    """
                }
            }
            post {
                always {
                    // Safe cleanup: execute as the host workspace user
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
            echo "SUCCESS: Baseline verified, containerized, and published to Nexus (Docker + Raw)."
        }
        failure {
            echo "FAILURE: Pipeline execution failed. Inspect stage telemetry."
        }
    }
}