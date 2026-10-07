pipeline {
    agent any

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        DOTNET_IMAGE                      = 'mcr.microsoft.com/dotnet/sdk:8.0-jammy'
        REGISTRY_HOST                     = 'nexus.homelab.local:8082' // Sonatype Nexus Docker repo
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
                sh """
                    # 1. Ephemeral non-root container directories inside mounted workspace
                    mkdir -p ${WORKSPACE}/.dotnet_cache ${WORKSPACE}/.nuget_packages ${WORKSPACE}/TestResults

                    # 2. Ephemeral .NET SDK container mapped to host UID/GID
                    docker run --rm \
                      -u \$(id -u):\$(id -g) \
                      -v ${WORKSPACE}:/src \
                      -w /src \
                      -e HOME=/src/.dotnet_cache \
                      -e DOTNET_CLI_HOME=/src/.dotnet_cache \
                      -e NUGET_PACKAGES=/src/.nuget_packages \
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
                        dotnet test tests/MissionControl.Tests/MissionControl.Tests.csproj \
                          -c Release \
                          --no-build \
                          --logger "trx;LogFileName=test_results.trx" \
                          --results-directory /src/TestResults
                      '
                """
            }
            post {
                always {
                    // Collect TRX evidence into Jenkins for audit records
                    junit allowEmptyResults: true, testResults: 'TestResults/*.trx'
                }
            }
        }

        stage('Multi-Stage Container Packaging') {
            steps {
                sh """
                    echo "--> Building hardened target container via Multi-Stage Dockerfile..."
                    docker build \
                      --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                      --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:latest .
                """
            }
        }
    }

    post {
        always {
            sh "rm -rf ${WORKSPACE}/.dotnet_cache ${WORKSPACE}/.nuget_packages"
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo "SUCCESS: Baseline verified and containerized: ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
        }
        failure {
            echo "FAILURE: Build broken. Investigation required."
        }
    }
}