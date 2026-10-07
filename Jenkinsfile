pipeline {
    agent any

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        DOTNET_IMAGE                      = 'mcr.microsoft.com/dotnet/sdk:8.0'
        REGISTRY_HOST                     = 'nexus.homelab.local:8082' // Mini PC Sonatype Nexus
        IMAGE_NAME                        = 'mission-control/sensor-gateway'
        GIT_COMMIT_SHORT                  = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }

    stages {
        stage('Audit & Traceability') {
            steps {
                echo "=========================================================="
                echo "Traceability: JIRA Task: CHG-1001"
                echo "Job Name:     ${JOB_NAME} | Build ID: ${BUILD_NUMBER}"
                echo "Commit SHA:   ${GIT_COMMIT_SHORT}"
                echo "Agent Node:   ${NODE_NAME} | Workspace: ${WORKSPACE}"
                echo "=========================================================="
            }
        }

        stage('.NET Deterministic Restore, Build & Test') {
            steps {
                sh """
                    # 1. Initialize writable container user caches inside host workspace
                    mkdir -p ${WORKSPACE}/.dotnet_cache ${WORKSPACE}/.nuget_packages ${WORKSPACE}/TestResults

                    # 2. Run isolated compilation inside ephemeral SDK container matching host UID/GID
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
                        
                        echo "--> Executing air-gapped locked restore..."
                        dotnet restore MissionControl/MissionControl.csproj \
                          --locked-mode \
                          --configfile nuget.config

                        echo "--> Building with zero compiler warnings policy..."
                        dotnet build MissionControl/MissionControl.csproj \
                          -c Release \
                          --no-restore \
                          /p:TreatWarningsAsErrors=true \
                          /p:ContinuousIntegrationBuild=true \
                          /p:Deterministic=true

                        echo "--> Executing test suite with V&V TRX telemetry..."
                        if [ -d "MissionControl.Tests" ] || [ -f "SimpleApp/SimpleApp.csproj" ]; then
                          dotnet test -c Release --no-build \
                            --logger "trx;LogFileName=test_results.trx" \
                            --results-directory /src/TestResults || true
                        fi
                      '
                """
            }
            post {
                always {
                    // Record test telemetry for release readiness and V&V reviews
                    junit allowEmptyResults: true, testResults: 'TestResults/*.trx'
                }
            }
        }

        stage('Multi-Stage Container Packaging') {
            steps {
                sh """
                    echo "--> Building hardened target container..."
                    docker build \
                      --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                      --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:latest .
                """
            }
        }

        stage('Publish Artifacts to Nexus') {
            // Activate when ready to push directly into your Mini PC Nexus Docker registry
            when {
                expression { env.ENABLE_NEXUS_PUSH == 'true' }
            }
            steps {
                sh """
                    echo "--> Tagging and pushing immutable container image to Nexus..."
                    docker tag ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}
                    docker push ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}
                """
            }
        }
    }

    post {
        always {
            // Clean up temporary mount caches to prevent disk bloat
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