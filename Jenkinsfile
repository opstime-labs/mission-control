pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
        timeout(time: 25, unit: 'MINUTES')
    }

    // Jenkins UI parameters for operator-controlled gates
    parameters {
        booleanParam(name: 'BUILD_SCAN_TEST_ENABLE', defaultValue: false, description: 'Check to build and scan the .NET solution with SonarQube SAST and V&V test suite')
        booleanParam(name: 'PUBLISH_DOCKER_IMAGE', defaultValue: true, description: 'Check to enable building and publishing multi-arch Docker image to Nexus')
        booleanParam(name: 'RUN_IMAGE_VULN_SCAN', defaultValue: false, description: 'Check to enable running a local Trivy vulnerability scan on the built Docker image')
        booleanParam(name: 'PUBLISH_RAW_RELEASE_ARTIFACTS', defaultValue: false, description: 'Check to enable publishing raw binary release artifacts to Nexus')
        booleanParam(name: 'DEPLOY_TO_SIL', defaultValue: true, description: 'Check to enable deploying the built Docker image to the SIL target node for integration testing')
        booleanParam(name: 'ROLLBACK', defaultValue: true, description: 'Check to enable rolling back to a previous deployment')
        string(name: 'JIRA_ISSUE_API_ENDPOINT', defaultValue: 'https://cp4learning.atlassian.net/rest/api/2/issue', description: 'Jira Cloud REST API endpoint for issue comments')
        string(name: 'HEALTH_CHECK_URL', defaultValue: 'http://10.0.0.163:8085/health', description: 'URL for health check endpoint')
    }

    // Environment variables for deterministic execution and defence audit trail
    environment {
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        DOTNET_SDK_IMAGE                  = 'mcr.microsoft.com/dotnet/sdk:8.0-jammy'
        SONAR_HOST_URL                    = 'http://10.0.0.182:9000'
        SONAR_PROJECT_KEY                 = 'mission-control-api'
        REGISTRY_HOST                     = 'nexus.homelab.local:8082'
        IMAGE_NAME                        = 'mission-control/sensor-gateway'
        NEXUS_RAW_BASE                    = 'http://10.0.0.182:8081/repository/raw-hosted'
        BUILDX_BUILDER                    = 'defence-builder'
        LOCAL_SCAN_TAG                    = "mission-control/sensor-gateway:local-scan"
        GIT_COMMIT_SHORT                  = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
        DEPLOY_SIL_AGENT_NAME             = 'sil-agent-01'
        BUILD_NODE_LABEL                  = 'built-in'
        
        // Canonical multibranch branch name; fallback to git rev-parse if running outside multibranch
        CURRENT_BRANCH                    = "${env.BRANCH_NAME ?: sh(script: 'git rev-parse --abbrev-ref HEAD 2>/dev/null', returnStdout: true).trim()}"        
        // Deployment host details
        DEPLOY_HOST_IP                    = "10.0.0.163"
        DEPLOY_HOST_USER                  = "deployer"
        DEPLOY_HOST_SSH                   = "${DEPLOY_HOST_USER}@${DEPLOY_HOST_IP}"
    }

    stages {
        stage('Stage 1: Configuration Audit & Traceability Gate') {
            steps {
                script {
                    // Check PR source branch, PR title, or fallback to the last 5 commit logs
                    def prSourceBranch = env.CHANGE_BRANCH ?: ""
                    def prTitle        = env.CHANGE_TITLE ?: ""
                    def commitLogs     = sh(script: "git log -5 --pretty=%B", returnStdout: true).trim()

                    def searchString = "${env.CURRENT_BRANCH} ${prSourceBranch} ${prTitle}\n${commitLogs}"
                    def jiraMatcher  = searchString =~ /(?i)([A-Z]{2,10}-\d+)/

                    if (!jiraMatcher) {
                        error("CONFIGURATION AUDIT GATE FAILURE: No Jira issue key found in PR source [${prSourceBranch}], title [${prTitle}], branch [${env.CURRENT_BRANCH}], or recent commits. Defence compliance requires an active work item.")
                    }

                    env.JIRA_KEY = jiraMatcher[0][1].toUpperCase()
                    currentBuild.displayName = "#${BUILD_NUMBER} [${env.JIRA_KEY}]"
                    currentBuild.description = "SHA: ${GIT_COMMIT_SHORT} | Ref: ${env.CURRENT_BRANCH}"

                    echo "=========================================================="
                    echo "Traceability Audit Gate: PASSED"
                    echo "Jira Work Item:     ${env.JIRA_KEY}"
                    echo "Commit SHA:         ${GIT_COMMIT_SHORT}"
                    echo "Canonical Branch:   ${env.CURRENT_BRANCH}"
                    echo "Target SIL Node:    ${env.DEPLOY_SIL_AGENT_NAME} (RPi 400)"
                    echo "=========================================================="
                }
            }
        }
        
        stage('Stage 2: .NET Restore, Build, Test & SonarQube SAST') {
            when {
                beforeAgent true
                expression { params.BUILD_SCAN_TEST_ENABLE == true }
            }
            steps {
                script {
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
                              ${DOTNET_SDK_IMAGE} \
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

        stage('Stage 3: Build Native Linux Image & Vulnerability Scan') {
            when {
                beforeAgent true
                expression { params.RUN_IMAGE_VULN_SCAN == true }
            }
            steps {
                sh """
                    set -euo pipefail
                    echo "--> Step 1: Building local amd64 container for security quarantine gate..."
                    docker buildx build \
                      --load \
                      --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                      --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                      -t ${LOCAL_SCAN_TAG} \
                      -f Dockerfile .

                    echo "--> Verifying image exists in local Docker engine..."
                    docker image inspect ${LOCAL_SCAN_TAG} > /dev/null

                    echo "--> Step 2: [V&V Security Gate] Scanning candidate container via Trivy..."
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity HIGH,CRITICAL \
                      --scanners vuln,secret \
                      --exit-code 0 \
                      --format table \
                      ${LOCAL_SCAN_TAG}
                """
            }
            post {
                always {
                    sh "docker rmi ${LOCAL_SCAN_TAG} || true"
                }
            }
        }

        stage('Stage 4: Multi-Arch Compilation & Publish Docker Image to Nexus') {
            when {
                beforeAgent true
                allOf {
                    expression { params.PUBLISH_DOCKER_IMAGE == true }
                    //expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail
                        echo "--> Authenticating Docker daemon to Nexus..."
                        echo "\$NEXUS_PASS" | docker login -u "\$NEXUS_USER" --password-stdin "${REGISTRY_HOST}"

                        echo "--> Ensuring active multi-arch builder..."
                        docker buildx use defence-builder

                        echo "--> Building & publishing multi-arch release images (amd64 + arm64) to Nexus..."
                        docker buildx build \
                          --platform linux/amd64,linux/arm64 \
                          --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                          --build-arg GIT_COMMIT=${GIT_COMMIT_SHORT} \
                          -t ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT} \
                          -t ${REGISTRY_HOST}/${IMAGE_NAME}:latest \
                          --push \
                          .

                        docker logout "${REGISTRY_HOST}"
                        docker builder prune -f --filter "until=24h"
                    """
                }
            }
        }

        stage('Stage 5: Publish Raw Binary Release to Nexus') {
            when {
                beforeAgent true
                allOf {
                    expression { params.PUBLISH_RAW_RELEASE_ARTIFACTS == true }
                    expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail
                        RELEASE_DIR="release_dist"
                        mkdir -p "\${RELEASE_DIR}"

                        ARTIFACT_NAME="mission-control-api-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}.tar.gz"
                        CHECKSUM_NAME="\${ARTIFACT_NAME}.sha256"

                        tar -czf "\${RELEASE_DIR}/\${ARTIFACT_NAME}" -C "${WORKSPACE}/publish_raw" .
                        cd "\${RELEASE_DIR}"
                        sha256sum "\${ARTIFACT_NAME}" > "\${CHECKSUM_NAME}"

                        UPLOAD_URL="${NEXUS_RAW_BASE}/sensor-gateway/${BUILD_NUMBER}"

                        echo "--> Uploading binary package: \${UPLOAD_URL}/\${ARTIFACT_NAME}..."
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${ARTIFACT_NAME}" \
                          "\${UPLOAD_URL}/\${ARTIFACT_NAME}"

                        echo "--> Uploading SHA-256 verification hash: \${UPLOAD_URL}/\${CHECKSUM_NAME}"
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${CHECKSUM_NAME}" \
                          "\${UPLOAD_URL}/\${CHECKSUM_NAME}"
                    """
                }
            }
            post {
                always {
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'release_dist/*.tar.gz, release_dist/*.sha256'
                    fingerprint 'release_dist/*.tar.gz'
                    sh "docker run --rm -v '${WORKSPACE}:/ws' alpine sh -c 'rm -rf /ws/release_dist /ws/publish_raw' || true"
                }
            }
        }

        // stage('Stage 6: Deploy to SIL Target Node (Running as Jenkins Agent)') {
        //     when {
        //         beforeAgent true
        //         allOf {
        //             expression { params.DEPLOY_TO_SIL == true }
        //             expression { return env.CURRENT_BRANCH in ['main', 'master'] }
        //         }
        //     }
        //     agent {
        //         label env.DEPLOY_SIL_AGENT_NAME
        //     }
        //     steps {
        //         sh '''
        //             set -euo pipefail
        //             mkdir -p /opt/mission-control
        //             cp deploy/scripts/deploy.sh /opt/mission-control/deploy.sh
        //             chmod 750 /opt/mission-control/deploy.sh
        //             /opt/mission-control/deploy.sh ${BUILD_NUMBER}-${GIT_COMMIT_SHORT}
        //         '''
        //     }
        // }

        // stage('Stage 6: Deploy to SIL Target Node (SSH Standalone)') {
        //     when {
        //         beforeAgent true
        //         allOf {
        //             expression { params.DEPLOY_TO_SIL == true }
        //             expression { return env.CURRENT_BRANCH in ['main', 'master'] }
        //         }
        //     }
        //     // Runs on standard Linux build worker (no agent needed on target hardware)
        //     agent { 
        //         label env.BUILD_NODE_LABEL 
        //     }
        //     steps {
        //         sshagent(credentials: ['sil-node-ssh-key']) {
        //             sh '''
        //                 set -euo pipefail                        
        //                 echo "--> Synchronizing deployment scripts to standalone SIL hardware..."
        //                 ssh -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST_SSH} "mkdir -p /tmp/mission-control"
        //                 scp -o StrictHostKeyChecking=accept-new deploy/scripts/deploy.sh ${DEPLOY_HOST_SSH}:/tmp/mission-control/deploy.sh
                       
        //                 echo "--> Triggering blue-green cutover for baseline ${BUILD_NUMBER}-${GIT_COMMIT_SHORT}..."
        //                 ssh ${DEPLOY_HOST_SSH} "chmod 750 /tmp/mission-control/deploy.sh && /tmp/mission-control/deploy.sh ${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"

        //                 echo "--> Cleaning up temporary deployment artifacts on SIL node..."
        //                 ssh -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST_SSH} "rm -rf /tmp/mission-control"
        //             '''
        //         }
        //     }            
        // }

        stage('Stage 6: Deploy to SIL Node via Ansible') {
            when {
                beforeAgent true
                allOf {
                    expression { params.DEPLOY_TO_SIL == true }
                    // Enforce deployment gate: only release/main baselines deploy to physical SIL hardware
                    //expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                }
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'sil-node-ssh-key', keyFileVariable: 'SSH_KEY_FILE'),
                    usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')
                ]) {
                    sh '''
                        set -euo pipefail

                        # 1. Resolve host workspace path for volume mounting (DooD)
                        JENKINS_HOME_HOST=$(docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination "/var/jenkins_home" }}{{ .Source }}{{ end }}{{ end }}')
                        REL_WORKSPACE="${WORKSPACE#/var/jenkins_home}"
                        HOST_WORKSPACE="${JENKINS_HOME_HOST}${REL_WORKSPACE}"
                        
                        KEY_TMP="./id_rsa_deploy"

                        # POSIX-compliant cleanup trap (EXIT runs on normal exit or failure via set -e)
                        trap 'rm -f "${KEY_TMP}"' EXIT INT TERM                        

                        # 2. Inspect active deployment slot on target SIL node
                        CURRENT_ACTIVE=$(ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST_USER}@${DEPLOY_HOST_IP} "cat /opt/mission-control/active_slot 2>/dev/null || echo 'blue'")
                        echo "--> Baseline active slot on SIL node: [${CURRENT_ACTIVE}]"

                        # 3. Stage ephemeral deployment credentials
                        cp "${SSH_KEY_FILE}" "${KEY_TMP}"
                        chmod 600 "${KEY_TMP}"

                        # 4. Execute containerized Ansible deployment (Zero Host Pollution)
                        docker run --rm \
                          -v "${HOST_WORKSPACE}:/workspace" \
                          -e ANSIBLE_HOST_KEY_CHECKING=False \
                          -w /workspace \
                          alpine/ansible:latest \
                          ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
                            --private-key "/workspace/${KEY_TMP#./}" \
                            -u ${DEPLOY_HOST_USER} \
                            -e "target_tag=${BUILD_NUMBER}-${GIT_COMMIT_SHORT}" \
                            -e "slot=${CURRENT_ACTIVE}" \
                            -e "nexus_user=${NEXUS_USER}" \
                            -e "nexus_pass=${NEXUS_PASS}"
                    '''
                }
            }
        } // end of Stage 6

        stage('Stage 7: Post-Deployment Smoke Test & Automated Rollback') {
            when {
                beforeAgent true
                allOf {
                    expression { params.ROLLBACK == true }
                    // Enforce deployment gate: only release/main baselines deploy to physical SIL hardware
                    //expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                }
            }
            steps {
                script {
                    try {
                        // Smoke test the production ingress on port 8085
                        sh '''
                            set -euo pipefail
                            echo "--> Running end-to-end smoke test against ingress port 8085..."
                            //curl --fail --retry 5 --retry-delay 2 --max-time 5 http://10.0.0.163:8085/health
                            curl --fail --retry 3 --retry-delay 2 --max-time 5 ${params.HEALTH_CHECK_URL}
                        '''
                    } catch (Exception e) {
                        echo "CRITICAL: Smoke test failed on target node! Initiating automated Ansible rollback..."
                        withCredentials([sshUserPrivateKey(credentialsId: 'sil-node-ssh-key', keyFileVariable: 'SSH_KEY_FILE')]) {
                            sh '''
                                set -euo pipefail
                        
                                # 1. Resolve host workspace path for volume mounting (DooD)
                                JENKINS_HOME_HOST=$(docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination "/var/jenkins_home" }}{{ .Source }}{{ end }}{{ end }}')
                                REL_WORKSPACE="${WORKSPACE#/var/jenkins_home}"
                                HOST_WORKSPACE="${JENKINS_HOME_HOST}${REL_WORKSPACE}"
                                
                                cp "${SSH_KEY_FILE}" ./id_rsa_deploy
                                chmod 600 ./id_rsa_deploy
                                trap 'rm -f ./id_rsa_deploy' EXIT

                                docker run --rm \
                                -v "${HOST_WORKSPACE}:/workspace" \
                                -e ANSIBLE_HOST_KEY_CHECKING=False \
                                -w /workspace \
                                alpine/ansible:latest \
                                ansible-playbook -i ansible/inventory.ini ansible/rollback.yml \
                                    --private-key /workspace/id_rsa_deploy \
                                    -u ${DEPLOY_HOST_USER}
                            '''
                        }
                        error("Deployment aborted and rolled back due to smoke test failure: ${e.message}")
                    }
                }
            } //
        } // end of Stage 7
    }  // end of stages

    post {
        always {
            sh 'docker image prune -f || true'
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            script {
                echo "SUCCESS: Pipeline verified for baseline ${BUILD_NUMBER} (${GIT_COMMIT_SHORT}) on branch [${env.CURRENT_BRANCH}]."
                
                if (env.CURRENT_BRANCH in ['main', 'master']) {
                    def dockerImageRef = "${env.REGISTRY_HOST}/${env.IMAGE_NAME}:${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    def rawTarballUrl  = "${env.NEXUS_RAW_BASE}/sensor-gateway/${BUILD_NUMBER}/mission-control-api-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}.tar.gz"
                    def rawShaUrl      = "${rawTarballUrl}.sha256"

                    // Multi-line Jira markup with native pipe separators
                    def jiraCommentBody = """*CONFIGURATION AUDIT: BASELINE DEPLOYED TO SIL*
h4. Build & Delivery Telemetry
* *Jenkins Build Run:* [#${BUILD_NUMBER}|${env.BUILD_URL}]
* *Baseline Branch / Commit:* ${env.CURRENT_BRANCH} / ${GIT_COMMIT_SHORT}
* *Target SIL Node:* ${env.DEPLOY_SIL_AGENT_NAME} (Raspberry Pi 400 - Slot Active)

h4. Vetted Release Artifacts (Sonatype Nexus OSS)
* *Container Registry:* [${dockerImageRef}|http://${dockerImageRef}]
* *Raw Binary Archive:* [mission-control-api-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}.tar.gz|${rawTarballUrl}]
* *Integrity Digest:* [SHA-256 Verification Hash|${rawShaUrl}]

_Audit baseline recorded for Controlled Goods and V&V compliance._"""

                    withCredentials([usernamePassword(credentialsId: 'jira-cloud-creds', 
                                                      usernameVariable: 'JIRA_USER', 
                                                      passwordVariable: 'JIRA_TOKEN')]) {
                        def jsonPayload = groovy.json.JsonOutput.toJson([body: jiraCommentBody])

                        sh """
                            curl -s -f -X POST \
                              -u "\${JIRA_USER}:\${JIRA_TOKEN}" \
                              -H "Accept: application/json" \
                              -H "Content-Type: application/json" \
                              -d '${jsonPayload}' \
                              "${params.JIRA_ISSUE_API_ENDPOINT}/${env.JIRA_KEY}/comment" || true
                        """
                    }
                } else {
                    echo "Notice: Branch [${env.CURRENT_BRANCH}] is an isolated branch. Skipping SIL deployment Jira telemetry to maintain clean audit baselines."
                }
            }
        }
        failure {
            script {
                echo "FAILURE: Pipeline execution halted on branch [${env.CURRENT_BRANCH}]."

                if (env.CURRENT_BRANCH in ['main', 'master']) {
                    withCredentials([usernamePassword(credentialsId: 'jira-cloud-creds', 
                                                      usernameVariable: 'JIRA_USER', 
                                                      passwordVariable: 'JIRA_TOKEN')]) {
                        sh """
                            curl -s -f -X POST \
                              -u "\${JIRA_USER}:\${JIRA_TOKEN}" \
                              -H "Accept: application/json" \
                              -H "Content-Type: application/json" \
                              -d '{"body": "BASELINE DEPLOYMENT HALTED: Build [#${BUILD_NUMBER}|${env.BUILD_URL}] (${GIT_COMMIT_SHORT}) on branch \\"${env.CURRENT_BRANCH}\\" failed execution.\\n\\nInspect Console Log: ${env.BUILD_URL}console"}' \
                              "${params.JIRA_ISSUE_API_ENDPOINT}/${env.JIRA_KEY}/comment" || true
                        """
                    }
                } else {
                    echo "Notice: Failure occurred on feature branch [${env.CURRENT_BRANCH}]. Skipping Jira baseline failure comment."
                }
            }
        }
    }
} // end of pipeline