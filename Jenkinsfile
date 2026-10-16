pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        skipDefaultCheckout(false)
    }

    parameters {
        // Stage 2: Code Quality & SAST Gate
        booleanParam(
            name: 'ENABLE_BUILD_AND_TEST',
            defaultValue: true,
            description: 'Compile .NET solution, execute TRX test suite, and run SonarQube SAST analysis'
        )

        // Stage 3 & Promotion Gating
        booleanParam(
            name: 'ENABLE_RAW_RELEASE_PUBLISH',
            defaultValue: true,
            description: 'Package and upload framework-dependent binary release archive (.tar.gz) to Nexus'
        )

        // Stage 4: Container Security & Registry
        booleanParam(
            name: 'ENABLE_TRIVY_SCAN',
            defaultValue: true,
            description: 'Scan candidate container with Trivy (fails pipeline on HIGH or CRITICAL findings)'
        )
        booleanParam(
            name: 'ENABLE_CONTAINER_PUBLISH',
            defaultValue: true,
            description: 'Build and push multi-architecture (amd64/arm64) Chiseled OCI image to Nexus registry'
        )
       
        // Stages 5 & 6: Deployment Execution
        choice(
            name: 'DEPLOY_STRATEGY',
            choices: ['ANSIBLE', 'STANDALONE_SSH', 'SKIP'],
            description: 'Deployment mechanism for the target SIL hardware node (sil-agent-01)'
        )

        // Stage 7: Ingress Verification
        booleanParam(
            name: 'ENABLE_INGRESS_HEALTH_CHECK',
            defaultValue: true,
            description: 'Verify service ingress health endpoints and execute automatic rollback ladder on failure'
        )

        // Target Infrastructure & Integrations
        string(
            name: 'HEALTH_CHECK_URL',
            defaultValue: 'http://10.0.0.163:8085/health',
            description: 'Authoritative health probe URL on the target SIL node'
        )
        string(
            name: 'JIRA_ISSUE_API_ENDPOINT',
            defaultValue: 'https://cp4learning.atlassian.net/rest/api/2/issue',
            description: 'Jira Cloud REST API base endpoint for traceability updates'
        )
    }

    environment {
        // .NET Runtime & Compilation Determinism
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO                     = 'true'
        ContinuousIntegrationBuild        = 'true'
        
        // Infrastructure Endpoints & Images
        REGISTRY_HOST                     = 'nexus.homelab.local:8082'
        IMAGE_NAME                        = 'mission-control/sensor-gateway'
        NEXUS_RAW_BASE                    = 'http://10.0.0.182:8081/repository/raw-hosted'
        DOTNET_BUILDER_IMAGE              = 'nexus.homelab.local:8082/infrastructure/dotnet-builder:10.0-jdk21-sonar9.0.1-r1'
        SONAR_HOST_URL                    = 'http://10.0.0.182:9000'
        SONAR_PROJECT_KEY                 = 'mission-control-api'
        
        // Target Node & SIL Parameters
        DEPLOY_SIL_AGENT_NAME             = 'sil-agent-01'
        DEPLOY_HOST_IP                    = '10.0.0.163'
        DEPLOY_HOST_USER                  = 'deployer'
        DEPLOY_HOST_SSH                   = "${DEPLOY_HOST_USER}@${DEPLOY_HOST_IP}"
        LOCAL_SCAN_TAG                    = "mission-control/sensor-gateway:scan-${BUILD_NUMBER}"
    }

    stages {
        stage('Stage 1: Configuration Audit & Traceability Gate') {
            steps {
                script {
                    // 1. Establish Canonical Branch & Git Metadata
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.CURRENT_BRANCH   = env.CHANGE_BRANCH ?: env.BRANCH_NAME ?: sh(script: "git rev-parse --abbrev-ref HEAD", returnStdout: true).trim()

                    // 2. Path-Filtering: Check if changes strictly affect documentation
                    def changedFiles = sh(
                        script: 'git diff --name-only HEAD~1 HEAD 2>/dev/null || true',
                        returnStdout: true
                    ).trim().split('\n').findAll { it.trim() }

                    def docExtensions  = ['.md', '.txt', '.pdf', '.docx', '.rst', '.adoc']
                    def docDirectories = ['docs/', 'documentation/', 'wiki/']

                    boolean hasCodeChanges = changedFiles.any { filePath ->
                        boolean isDocExt = docExtensions.any { ext -> filePath.toLowerCase().endsWith(ext) }
                        boolean isDocDir = docDirectories.any { dir -> filePath.toLowerCase().startsWith(dir) }
                        return !(isDocExt || isDocDir)
                    }

                    if (!hasCodeChanges && changedFiles.size() > 0) {
                        currentBuild.description = "Skipped: Documentation changes only (*.md)"
                        currentBuild.result = 'NOT_BUILT'
                        error("DOCS_ONLY_SKIP: Commit strictly touches documentation. Terminating pipeline.")
                    }

                    // 3. Jira Audit Gate: Verify Issue Key in PR or Commits
                    def prSourceBranch = env.CHANGE_BRANCH ?: ""
                    def prTitle        = env.CHANGE_TITLE ?: ""
                    def commitLogs     = sh(script: "git log -5 --pretty=%B", returnStdout: true).trim()

                    def searchString = "${env.CURRENT_BRANCH} ${prSourceBranch} ${prTitle}\n${commitLogs}"
                    def jiraMatcher  = searchString =~ /(?i)([A-Z]{2,10}-\d+)/

                    if (!jiraMatcher) {
                        error("CONFIGURATION AUDIT FAILURE: No Jira issue key found. Controlled Goods and IEEE 828 standards mandate an active tracking ticket.")
                    }

                    env.JIRA_ID = jiraMatcher[0][1].toUpperCase()
                    currentBuild.displayName = "#${BUILD_NUMBER} [${env.JIRA_ID}]"
                    currentBuild.description = "SHA: ${env.GIT_COMMIT_SHORT} | Branch: ${env.CURRENT_BRANCH}"

                    echo "=========================================================="
                    echo "Traceability Audit Gate: PASSED"
                    echo "Jira Work Item:     ${env.JIRA_ID}"
                    echo "Commit SHA:         ${env.GIT_COMMIT_SHORT}"
                    echo "Canonical Branch:   ${env.CURRENT_BRANCH}"
                    echo "Target SIL Node:    ${env.DEPLOY_SIL_AGENT_NAME} (${env.DEPLOY_HOST_IP})"
                    echo "=========================================================="
                }
            }
        }

        stage('Stage 2: .NET 10 Restore, Build, Test & SonarQube SAST') {
            when {
                beforeAgent true
                expression { params.ENABLE_BUILD_AND_TEST == true }
            }
            steps {
                script {
                    def jenkinsHomeHost = sh(
                        script: "docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination \"/var/jenkins_home\" }}{{ .Source }}{{ end }}{{ end }}'",
                        returnStdout: true
                    ).trim()
                    def hostWorkspace = WORKSPACE.replace('/var/jenkins_home', jenkinsHomeHost)

                    withCredentials([
                        string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN'),
                        usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')
                    ]) {
                        sh """
                            set -euo pipefail

                            # 1. Authenticate to air-gapped Nexus registry
                            echo "\$NEXUS_PASS" | docker login -u "\$NEXUS_USER" --password-stdin "${REGISTRY_HOST}"
                            trap 'docker logout "${REGISTRY_HOST}"' EXIT

                            # 2. Run deterministic build, test, and SAST inside pre-baked .NET 10 runner
                            docker run --rm \
                              -v "${hostWorkspace}:/workspace" \
                              -w /workspace \
                              --tmpfs /tmp:rw,exec,nosuid,size=2048m \
                              -e HOME=/tmp \
                              -e DOTNET_CLI_HOME=/tmp/.dotnet \
                              -e NUGET_PACKAGES=/tmp/.nuget/packages \
                              -e PATH="/usr/local/bin:/usr/bin:/bin" \
                              -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
                              -e ContinuousIntegrationBuild=true \
                              -e SONAR_TOKEN="${SONAR_TOKEN}" \
                              ${DOTNET_BUILDER_IMAGE} \
                              bash -c '
                                set -euo pipefail

                                echo "--> [Air-Gap Staging] Restoring dependencies in locked mode..."
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

                                echo "--> [V&V Gate] Enforcing zero compiler warnings & deterministic flags..."
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

        stage('Stage 3: Publish Raw Binary Release Archive to Nexus') {
            when {
                beforeAgent true
                anyOf {                    
                    // Automatically on main 
                    expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                    // Explicit manual opt-in on feature branches/PRs
                    expression { params.ENABLE_RAW_RELEASE_PUBLISH == true }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh """
                        set -euo pipefail
                        RELEASE_DIR="release_dist"
                        mkdir -p "\${RELEASE_DIR}"

                        ARTIFACT_NAME="mission-control-api-${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}.tar.gz"
                        CHECKSUM_NAME="\${ARTIFACT_NAME}.sha256"

                        echo "--> Packaging binary release archive..."
                        tar -czf "\${RELEASE_DIR}/\${ARTIFACT_NAME}" -C "${WORKSPACE}/publish_raw" .
                        
                        cd "\${RELEASE_DIR}"
                        sha256sum "\${ARTIFACT_NAME}" > "\${CHECKSUM_NAME}"

                        UPLOAD_URL="${NEXUS_RAW_BASE}/sensor-gateway/${BUILD_NUMBER}"

                        echo "--> Publishing binary package to Nexus raw repository: \${UPLOAD_URL}/\${ARTIFACT_NAME}..."
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${ARTIFACT_NAME}" \
                          "\${UPLOAD_URL}/\${ARTIFACT_NAME}"

                        echo "--> Publishing SHA-256 verification hash: \${UPLOAD_URL}/\${CHECKSUM_NAME}..."
                        curl -s -f -u "\${NEXUS_USER}:\${NEXUS_PASS}" \
                          --upload-file "\${CHECKSUM_NAME}" \
                          "\${UPLOAD_URL}/\${CHECKSUM_NAME}"
                    """
                }
            }
        }

        stage('Stage 4: Container Security Gate & Multi-Arch Publish') {
            when {
                beforeAgent true                
                expression { params.ENABLE_CONTAINER_PUBLISH == true }                
            }
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'nexus-docker-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                        sh """
                            set -euo pipefail

                            # 1. Build local container image for vulnerability gating
                            echo "--> Building candidate container with Chiseled runtime..."
                            docker buildx build \
                              --load \
                              --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                              --build-arg GIT_COMMIT=${env.GIT_COMMIT_SHORT} \
                              -t ${LOCAL_SCAN_TAG} \
                              -f Dockerfile .

                            # 2. Enforce Trivy vulnerability scanning if enabled
                            if [ "${params.ENABLE_TRIVY_SCAN}" = "true" ]; then
                                echo "--> [V&V Security Gate] Scanning candidate container via Trivy (--exit-code 1)..."
                                docker run --rm \
                                  -v /var/run/docker.sock:/var/run/docker.sock \
                                  aquasec/trivy:latest image \
                                  --severity HIGH,CRITICAL \
                                  --scanners vuln,secret \
                                  --exit-code 1 \
                                  --format table \
                                  ${LOCAL_SCAN_TAG}
                            fi

                            # 3. Publish multi-arch images if on main/master baseline
                            if [ "${env.CURRENT_BRANCH}" = "main" ] || [ "${env.CURRENT_BRANCH}" = "master" ]; then
                                echo "--> Authenticating to private Nexus OCI registry..."
                                echo "\$NEXUS_PASS" | docker login -u "\$NEXUS_USER" --password-stdin "${REGISTRY_HOST}"
                                trap 'docker logout "${REGISTRY_HOST}"' EXIT

                                echo "--> Building & publishing multi-arch release images (amd64 + arm64)..."
                                docker buildx build \
                                  --platform linux/amd64,linux/arm64 \
                                  --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                                  --build-arg GIT_COMMIT=${env.GIT_COMMIT_SHORT} \
                                  -t ${REGISTRY_HOST}/${IMAGE_NAME}:${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT} \
                                  -t ${REGISTRY_HOST}/${IMAGE_NAME}:latest \
                                  --push \
                                  -f Dockerfile .

                                docker builder prune -f --filter "until=24h"
                            fi
                        """
                    }
                }
            }
            post {
                always {
                    sh 'docker rmi "${LOCAL_SCAN_TAG}" 2>/dev/null || true'
                }
            }
        }

        stage('Stage 5: Deploy to SIL Hardware Node via Ansible') {
            when {
                beforeAgent true
                allOf {
                    expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                    expression { params.DEPLOY_STRATEGY == 'ANSIBLE' }                    
                }
            }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'sil-node-ssh-key', keyFileVariable: 'SSH_KEY_FILE'),
                    file(credentialsId: 'ansible-vault-password-file', variable: 'VAULT_KEY_FILE')
                ]) {
                    sh '''
                        set -euo pipefail

                        JENKINS_HOME_HOST=$(docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination "/var/jenkins_home" }}{{ .Source }}{{ end }}{{ end }}')
                        REL_WORKSPACE="${WORKSPACE#/var/jenkins_home}"
                        HOST_WORKSPACE="${JENKINS_HOME_HOST}${REL_WORKSPACE}"
                        
                        KEY_TMP="./id_rsa_deploy"
                        VAULT_TMP="./vault_pass_tmp"

                        cp "${SSH_KEY_FILE}" "${KEY_TMP}"
                        cp "${VAULT_KEY_FILE}" "${VAULT_TMP}"
                        chmod 600 "${KEY_TMP}" "${VAULT_TMP}"

                        # POSIX unified trap: cleanly scrubs all transient secrets on exit
                        trap 'shred -u -z -v -n 3 "${KEY_TMP}" "${VAULT_TMP}" 2>/dev/null || rm -f "${KEY_TMP}" "${VAULT_TMP}"' EXIT INT TERM

                        CURRENT_ACTIVE=$(ssh -i "${KEY_TMP}" -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST_USER}@${DEPLOY_HOST_IP} "cat /opt/mission-control/active_slot 2>/dev/null || echo 'blue'")
                        echo "--> Baseline active slot on target SIL node: [${CURRENT_ACTIVE}]"

                        # Execute containerized Ansible deployment
                        docker run --rm \
                          -v "${HOST_WORKSPACE}:/workspace" \
                          -e ANSIBLE_HOST_KEY_CHECKING=False \
                          -w /workspace \
                          alpine/ansible:latest \
                          ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
                            --private-key "/workspace/${KEY_TMP#./}" \
                            --vault-password-file "/workspace/${VAULT_TMP#./}" \
                            -u "${DEPLOY_HOST_USER}" \
                            -e "target_tag=${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    '''
                }
            }
        }

        stage('Stage 6: Deploy to SIL Hardware Node (Standalone SSH)') {
            when {
                beforeAgent true
                allOf {
                    expression { params.DEPLOY_STRATEGY == 'STANDALONE_SSH' }
                    expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                }
            }
            steps {
                sshagent(credentials: ['sil-node-ssh-key']) {
                    sh '''
                        set -euo pipefail
                        echo "--> Synchronizing deployment scripts to standalone SIL hardware..."
                        ssh -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST_SSH} "mkdir -p /tmp/mission-control"
                        scp -o StrictHostKeyChecking=accept-new deploy/scripts/deploy.sh ${DEPLOY_HOST_SSH}:/tmp/mission-control/deploy.sh
                       
                        echo "--> Executing cutover for baseline ${BUILD_NUMBER}-${GIT_COMMIT_SHORT}..."
                        ssh ${DEPLOY_HOST_SSH} "chmod 750 /tmp/mission-control/deploy.sh && /tmp/mission-control/deploy.sh ${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"

                        echo "--> Cleaning up temporary staging directories on SIL target..."
                        ssh -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST_SSH} "rm -rf /tmp/mission-control"
                    '''
                }
            }
        }

        stage('Stage 7: Ingress Verification & Automated Recovery Ladder') {
            when {
                beforeAgent true
                allOf {
                    expression { params.DEPLOY_STRATEGY != 'SKIP' }
                    expression { params.ENABLE_INGRESS_HEALTH_CHECK == true }
                    expression { return env.CURRENT_BRANCH in ['main', 'master'] }
                }
            }
            steps {
                script {
                    try {
                        echo "--> Verifying Ingress readiness on port 8085..."
                        sh """
                            set -euo pipefail
                            curl --fail --retry 5 --retry-delay 2 --max-time 5 "${params.HEALTH_CHECK_URL}"
                        """
                        echo "SUCCESS: Primary ingress probe verified."
                    } catch (Exception primaryError) {
                        echo "WARNING: Primary verification failed! Invoking Phase 1 automated rollback..."
                        try {
                            withCredentials([
                                sshUserPrivateKey(credentialsId: 'sil-node-ssh-key', keyFileVariable: 'SSH_KEY_FILE'),
                                file(credentialsId: 'ansible-vault-password-file', variable: 'VAULT_KEY_FILE')
                            ]) {
                                sh '''
                                    set -euo pipefail
                                    JENKINS_HOME_HOST=$(docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination "/var/jenkins_home" }}{{ .Source }}{{ end }}{{ end }}')
                                    REL_WORKSPACE="${WORKSPACE#/var/jenkins_home}"
                                    HOST_WORKSPACE="${JENKINS_HOME_HOST}${REL_WORKSPACE}"
                                    
                                    KEY_TMP="./id_rsa_deploy"
                                    VAULT_TMP="./vault_pass_tmp"
                                    cp "${SSH_KEY_FILE}" "${KEY_TMP}"
                                    cp "${VAULT_KEY_FILE}" "${VAULT_TMP}"
                                    chmod 600 "${KEY_TMP}" "${VAULT_TMP}"
                                    trap 'shred -u -z -v -n 3 "${KEY_TMP}" "${VAULT_TMP}" 2>/dev/null || rm -f "${KEY_TMP}" "${VAULT_TMP}"' EXIT INT TERM

                                    docker run --rm \
                                      -v "${HOST_WORKSPACE}:/workspace" \
                                      -e ANSIBLE_HOST_KEY_CHECKING=False \
                                      -w /workspace \
                                      alpine/ansible:latest \
                                      ansible-playbook -i ansible/inventory.ini ansible/rollback.yml \
                                        --private-key "/workspace/${KEY_TMP#./}" \
                                        --vault-password-file "/workspace/${VAULT_TMP#./}" \
                                        -u "${DEPLOY_HOST_USER}"
                                '''
                            }

                            echo "--> Verifying restored fallback slot ingress..."
                            sh """
                                set -euo pipefail
                                curl --fail --retry 3 --retry-delay 2 --max-time 5 "${params.HEALTH_CHECK_URL}"
                            """
                            echo "RECOVERY CONFIRMED: Rollback succeeded. Target node operating in degraded single-slot mode."
                            currentBuild.result = 'UNSTABLE'

                            // Annotate Jira regarding degraded mode using ephemeral curl config
                            withCredentials([usernamePassword(credentialsId: 'jira-cloud-creds', usernameVariable: 'JIRA_USER', passwordVariable: 'JIRA_TOKEN')]) {
                                sh """
                                    set -euo pipefail
                                    CURL_CONF=\$(mktemp)
                                    chmod 600 "\${CURL_CONF}"
                                    trap 'rm -f "\${CURL_CONF}"' EXIT INT TERM
                                    
                                    AUTH_B64=\$(printf "%s:%s" "${JIRA_USER}" "${JIRA_TOKEN}" | base64 | tr -d '\\n')
                                    echo "header = \\"Authorization: Basic \${AUTH_B64}\\"" > "\${CURL_CONF}"

                                    curl -s -f -X POST \
                                      -K "\${CURL_CONF}" \
                                      -H "Accept: application/json" \
                                      -H "Content-Type: application/json" \
                                      -d '{"body": "⚠️ DEGRADED DEPLOYMENT ALERT: Build [#${BUILD_NUMBER}|${env.BUILD_URL}] failed smoke tests. Automated rollback succeeded. Target node is running in DEGRADED SINGLE-SLOT MODE on previous baseline."}' \
                                      "${params.JIRA_ISSUE_API_ENDPOINT}/${env.JIRA_ID}/comment"
                                """
                            }

                        } catch (Exception rollbackError) {
                            echo "CRITICAL DOUBLE FAULT: Rollback failed! Invoking Phase 2 Fail-Safe Lockdown..."
                            withCredentials([sshUserPrivateKey(credentialsId: 'sil-node-ssh-key', keyFileVariable: 'SSH_KEY_FILE')]) {
                                sh '''
                                    set -euo pipefail
                                    JENKINS_HOME_HOST=$(docker inspect jenkins-controller --format '{{ range .Mounts }}{{ if eq .Destination "/var/jenkins_home" }}{{ .Source }}{{ end }}{{ end }}')
                                    REL_WORKSPACE="${WORKSPACE#/var/jenkins_home}"
                                    HOST_WORKSPACE="${JENKINS_HOME_HOST}${REL_WORKSPACE}"
                                    
                                    KEY_TMP="./id_rsa_deploy"
                                    cp "${SSH_KEY_FILE}" "${KEY_TMP}"
                                    chmod 600 "${KEY_TMP}"
                                    trap 'shred -u -z -v -n 3 "${KEY_TMP}" 2>/dev/null || rm -f "${KEY_TMP}"' EXIT INT TERM
                                    
                                    docker run --rm \
                                      -v "${HOST_WORKSPACE}:/workspace" \
                                      -e ANSIBLE_HOST_KEY_CHECKING=False \
                                      -w /workspace \
                                      alpine/ansible:latest \
                                      ansible-playbook -i ansible/inventory.ini ansible/fail_safe.yml \
                                        --private-key "/workspace/${KEY_TMP#./}" \
                                        -u "${DEPLOY_HOST_USER}"
                                '''
                            }
                            error("CRITICAL DOUBLE FAULT: Both deployment slots failed. SIL node locked in 503 Fail-Safe mode for root-cause forensic analysis.")
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            echo "--> Cleaning up pipeline workspace and dangling builder caches..."
            sh 'docker image prune -f || true'
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            script {
                echo "SUCCESS: Baseline ${BUILD_NUMBER} (${env.GIT_COMMIT_SHORT}) verified on branch [${env.CURRENT_BRANCH}]."
                
                if (env.CURRENT_BRANCH in ['main', 'master']) {
                    def dockerImageRef = "${env.REGISTRY_HOST}/${env.IMAGE_NAME}:${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                    def rawTarballUrl  = "${env.NEXUS_RAW_BASE}/sensor-gateway/${BUILD_NUMBER}/mission-control-api-${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}.tar.gz"
                    def rawShaUrl      = "${rawTarballUrl}.sha256"

                    def jiraCommentBody = """*CONFIGURATION AUDIT: BASELINE DEPLOYED TO SIL*
h4. Build & Delivery Telemetry
* *Jenkins Build Run:* [#${BUILD_NUMBER}|${env.BUILD_URL}]
* *Baseline Branch / Commit:* ${env.CURRENT_BRANCH} / ${env.GIT_COMMIT_SHORT}
* *Target SIL Node:* ${env.DEPLOY_SIL_AGENT_NAME} (${env.DEPLOY_HOST_IP} - Active Slot)

h4. Vetted Release Artifacts (Sonatype Nexus OSS)
* *Container Registry:* [${dockerImageRef}|http://${dockerImageRef}]
* *Raw Binary Archive:* [mission-control-api-${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}.tar.gz|${rawTarballUrl}]
* *Integrity Digest:* [SHA-256 Verification Hash|${rawShaUrl}]

_Audit baseline recorded for Controlled Goods and V&V compliance._"""

                    withCredentials([usernamePassword(credentialsId: 'jira-cloud-creds', usernameVariable: 'JIRA_USER', passwordVariable: 'JIRA_TOKEN')]) {
                        def jsonPayload = groovy.json.JsonOutput.toJson([body: jiraCommentBody])
                        sh """
                            set -euo pipefail
                            CURL_CONF=\$(mktemp)
                            chmod 600 "\${CURL_CONF}"
                            trap 'rm -f "\${CURL_CONF}"' EXIT INT TERM
                            
                            AUTH_B64=\$(printf "%s:%s" "${JIRA_USER}" "${JIRA_TOKEN}" | base64 | tr -d '\\n')
                            echo "header = \\"Authorization: Basic \${AUTH_B64}\\"" > "\${CURL_CONF}"

                            curl -s -f -X POST \
                              -K "\${CURL_CONF}" \
                              -H "Accept: application/json" \
                              -H "Content-Type: application/json" \
                              -d '${jsonPayload}' \
                              "${params.JIRA_ISSUE_API_ENDPOINT}/${env.JIRA_ID}/comment" || echo "[WARNING] Jira comment failed to post."
                        """
                    }
                }
            }
        }
        failure {
            script {
                echo "FAILURE: Pipeline execution halted on branch [${env.CURRENT_BRANCH}]."

                if (env.CURRENT_BRANCH in ['main', 'master'] && env.JIRA_ID) {
                    withCredentials([usernamePassword(credentialsId: 'jira-cloud-creds', usernameVariable: 'JIRA_USER', passwordVariable: 'JIRA_TOKEN')]) {
                        sh """
                            set -euo pipefail
                            CURL_CONF=\$(mktemp)
                            chmod 600 "\${CURL_CONF}"
                            trap 'rm -f "\${CURL_CONF}"' EXIT INT TERM
                            
                            AUTH_B64=\$(printf "%s:%s" "${JIRA_USER}" "${JIRA_TOKEN}" | base64 | tr -d '\\n')
                            echo "header = \\"Authorization: Basic \${AUTH_B64}\\"" > "\${CURL_CONF}"

                            curl -s -f -X POST \
                              -K "\${CURL_CONF}" \
                              -H "Accept: application/json" \
                              -H "Content-Type: application/json" \
                              -d '{"body": "BASELINE DEPLOYMENT HALTED: Build [#${BUILD_NUMBER}|${env.BUILD_URL}] (${env.GIT_COMMIT_SHORT}) on branch \\"${env.CURRENT_BRANCH}\\" failed execution.\\n\\nInspect Console Log: ${env.BUILD_URL}console"}' \
                              "${params.JIRA_ISSUE_API_ENDPOINT}/${env.JIRA_ID}/comment" || echo "[WARNING] Jira failure comment failed to post."
                        """
                    }
                }
            }
        }
    }
}