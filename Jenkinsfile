pipeline {
    agent any

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        DOTNET_IMAGE                      = 'mcr.microsoft.com/dotnet/sdk:8.0-jammy'
        REGISTRY_HOST                     = 'nexus.homelab.local:8082'
        IMAGE_NAME                        = 'mission-control/sensor-gateway'
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

        stage('.NET Deterministic Restore, Build & Test') {
            steps {
                script {
                    def hostWorkspace = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim() + "/workspace/${JOB_NAME}"

                    sh """
                        docker run --rm \
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

        stage('Multi-Stage Container Packaging') {
            steps {
                sh """
                    echo "--> Sanitizing build context and streaming to Docker daemon..."
                    tar --exclude='.git' \
                        --exclude='TestResults' \
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

        stage('Publish to Nexus Registry') {
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
    }

    stage('Publish Raw Artifacts to Nexus') {
            steps {
                script {
                    def hostWorkspace = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim() + "/workspace/${JOB_NAME}"

                    // 1. Generate clean framework-dependent release binaries inside the SDK container
                    sh """
                        docker run --rm \
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

                    // 2. Archive, hash, and upload to the exact Nexus raw-hosted endpoint
                    withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                        sh """
                            set -euo pipefail

                            RELEASE_DIR="release_dist"
                            mkdir -p "\${RELEASE_DIR}"

                            ARTIFACT_NAME="mission-control-api-\${BUILD_NUMBER}-\${GIT_COMMIT_SHORT}.tar.gz"
                            CHECKSUM_NAME="\${ARTIFACT_NAME}.sha256"

                            echo "--> Compressing binary release package..."
                            tar -czf "\${RELEASE_DIR}/\${ARTIFACT_NAME}" -C /var/jenkins_home/workspace/${JOB_NAME}/publish_raw .

                            echo "--> Computing cryptographic SHA-256 baseline manifest..."
                            cd "\${RELEASE_DIR}"
                            sha256sum "\${ARTIFACT_NAME}" > "\${CHECKSUM_NAME}"

                            NEXUS_RAW_ENDPOINT="http://10.0.0.182:8081/repository/raw-hosted/sensor-gateway/\${BUILD_NUMBER}"

                            echo "--> Uploading binary package to Nexus: \${NEXUS_RAW_ENDPOINT}/\${ARTIFACT_NAME}"
                            curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                              --upload-file "\${ARTIFACT_NAME}" \
                              "\${NEXUS_RAW_ENDPOINT}/\${ARTIFACT_NAME}"

                            echo "--> Uploading SHA-256 verification hash: \${NEXUS_RAW_ENDPOINT}/\${CHECKSUM_NAME}"
                            curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                              --upload-file "\${CHECKSUM_NAME}" \
                              "\${NEXUS_RAW_ENDPOINT}/\${CHECKSUM_NAME}"

                            echo "--> Nexus raw upload completed and verified."
                        """
                    }
                }
            }
            post {
                always {
                    sh "rm -rf release_dist publish_raw"
                }
            }
    }

    post {
        always {
            cleanWs notFailBuild: true
        }
        success {
            echo "SUCCESS: Baseline verified, containerized, and published: ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
        }
        failure {
            echo "FAILURE: Build broken. Investigation required."
        }
    }
}