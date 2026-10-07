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
    }

    post {
        always {
            // Clean workspace cleanly without deferred locks
            cleanWs notFailBuild: true
        }
        success {
            echo "SUCCESS: Baseline verified and containerized: ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
        }
        failure {
            echo "FAILURE: Build broken. Investigation required."
        }
    }
}