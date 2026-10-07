pipeline {
    agent any

    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        REGISTRY_HOST               = 'nexus.homelab.local:8082' // Sonatype Nexus Docker repo
        IMAGE_NAME                  = 'mission-critical/sensor-gateway'
        GIT_COMMIT_SHORT            = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }

    stages {
        stage('Audit & Traceability') {
            steps {
                echo "=========================================================="
                echo "Job: ${JOB_NAME} | Build: ${BUILD_NUMBER}"
                echo "Commit SHA: ${GIT_COMMIT_SHORT}"
                echo "Workspace: ${WORKSPACE}"
                echo "=========================================================="
            }
        }

        stage('.NET Deterministic Build & Test') {
            agent {
                docker {
                    image 'mcr.microsoft.com/dotnet/sdk:8.0'
                    reuseNode true
                }
            }
            steps {
                // Locked restore ensures reproducibility required in defence environments
                sh 'dotnet restore --locked-mode'
                
                // Enforce zero compiler warnings
                sh 'dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true /p:ContinuousIntegrationBuild=true'
                
                // Run unit tests with detailed console logger
                sh 'dotnet test -c Release --no-build --logger "console;verbosity=normal"'
            }
        }

        stage('Multi-Stage Container Build') {
            steps {
                script {
                    def fullImageTag = "${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    
                    // Build container injecting Controlled Goods / traceability metadata
                    sh """
                        docker build \
                          --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                          --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                          -t ${fullImageTag} \
                          -t ${IMAGE_NAME}:latest .
                    """
                }
            }
        }

        stage('Publish Artifacts') {
            steps {
                script {
                    echo "Tagging and pushing container image to Nexus..."
                    // Uncomment once Sonatype Nexus is running on your Mini PC
                    // sh "docker tag ${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    // sh "docker push ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                }
            }
        }
    }

    post {
        always {
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo "CI Baseline Verified. Ready for Target Node / SIL staging."
        }
        failure {
            echo "Pipeline Failed. Immediate triage required."
        }
    }
}
