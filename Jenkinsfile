pipeline {
    agent any

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        ContinuousIntegrationBuild  = 'true'
        REGISTRY_HOST               = 'nexus.homelab.local:8082' // Sonatype Nexus Docker repo
        DOTNET_IMAGE                = 'mcr.microsoft.com/dotnet/sdk:8.0'
        IMAGE_NAME                  = 'mission-control/sensor-gateway'
        GIT_COMMIT_SHORT            = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }

    stages {
        stage('Audit & Traceability') {
            steps {
                echo "=========================================================="
                echo "Traceability: JIRA/Task: CHG-1001"
                echo "Job: ${JOB_NAME} | Build: ${BUILD_NUMBER}"
                echo "Commit SHA: ${GIT_COMMIT_SHORT}"
                echo "Agent Node: ${NODE_NAME} | Workspace: ${WORKSPACE}"
                echo "=========================================================="
            }
        }

        stage('.NET Deterministic Restore & Build') {
            steps {
                // Run inside an ephemeral .NET SDK container mounting the workspace
                sh """
                    docker run --rm \
                      -u \$(id -u):\$(id -g) \
                      -v ${WORKSPACE}:/src \
                      -w /src \
                      -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
                      -e ContinuousIntegrationBuild=true \
                      ${DOTNET_IMAGE} \
                      bash -c '
                        set -e
                        dotnet restore --locked-mode --configfile nuget.config
                        dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true /p:ContinuousIntegrationBuild=true
                        dotnet test -c Release --no-build --logger "console;verbosity=normal"
                      '
                """
            }
        }

        stage('Multi-Stage Container Packaging') {
            steps {
                sh """
                    docker build \
                      --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                      --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} \
                      -t ${IMAGE_NAME}:latest .
                """
            }
        }

        // Note: The following stage is commented out to prevent accidental pushes to Nexus during development.
        stage('Publish Artifacts') {
            steps {
                script {
                    echo "Tagging and pushing container image to Nexus..."
                    // Uncomment once Sonatype Nexus is running on your Mini PC
                    sh "docker tag ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    sh "docker push ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                }
            }
        }
    }

    post {
        always {
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo "CI Baseline Verified. Image packaged: ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
        }
        failure {
            echo "Pipeline Failed. Immediate triage required."
        }
    }
}