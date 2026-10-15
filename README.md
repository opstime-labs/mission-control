# **MissionControl: Defence-Grade CI/CD & SIL Deployment Pipeline for C\#/.NET 10**

An enterprise-grade, auditable CI/CD delivery pipeline and deployment framework designed for mission-critical C\#/.NET naval and sensor systems\[cite: 4, 5\]. Built to meet the operational demands of defence Systems Integration Laboratories (SIL) and tactical edge environments, this repository demonstrates reproducible builds, air-gapped artifact governance, container runtime hardening, Hardware-in-the-Loop pre-flight verification, and autonomous fault recovery.

## **1\. Executive Summary & Architecture Highlights**

* **Reproducible .NET 8 Compilation:** Solution-wide deterministic compilation (/p:Deterministic=true), compiler warning zero-tolerance (/p:TreatWarningsAsErrors=true), and strict SHA-512 dependency locking via packages.lock.json with dotnet restore \--locked-mode\.  
* **Air-Gapped Supply Chain Governance:** Self-hosted Sonatype Nexus OSS hosting private OCI Docker registries and local NuGet feeds with Package Source Mapping enabled. Zero runtime internet dependencies\[cite: 4, 5\].  
* **Hardened Distroless Packaging:** Multi-stage Docker builds targeting **Ubuntu Chiseled** (\[mcr.microsoft.com/dotnet/aspnet:8.0-jammy-chiseled\](https\://mcr.microsoft.com/dotnet/aspnet:8.0-jammy-chiseled)), running as an unprivileged UID (\$APP\_UID), devoid of shells, package managers, and root access.  
* **Automated Static & Dynamic Security Gates:** Jenkins pipeline gating on SonarQube quality gates (sonar.qualitygate.wait=true) and Trivy vulnerability assessments (--exit-code 1 on HIGH/CRITICAL CVEs)\[cite: 4, 5\].  
* **Hardware-in-the-Loop (HIL) Pre-Flight Gating:** Ansible pre-flight checks validating host environmental boundaries (thermal throttling, memory/disk pressure) and kernel-level character bus bindings (/dev/i2c-1, /dev/gpiomem) before cutover\[cite: 4, 5\].  
* **Blue/Green Zero-Downtime Deployment:** Atomic ingress routing over custom unprivileged sockets (port 8085\) using NGINX upstream reconfiguration and dynamic Docker IPAM discovery.  
* **Defense-in-Depth Automated Rollback Ladder:**  
  1. *Pipeline-Level Automated Rollback:* Reverts to the standby slot if health checks or integration smoke tests fail\[cite: 4, 5\].  
  2. *Double-Fault Critical Stop Protocol:* Quarantines the node into an HTTP 503 Maintenance Mode with Retry-After: 300 headers and dumps kernel/process forensics if both execution slots fail.  
  3. *Autonomous Host Supervisor (sil-watchdog.service):* Host-level systemd daemon executing out-of-band rollback if central CI connectivity drops.  
* **End-to-End Audit Traceability:** Bidirectional commit-to-issue tracking updating Jira issues via authenticated REST APIs on build, verification, rollback, or quarantine events\[cite: 4, 5\].

## **2\. System Architecture**

Plaintext  
                                  CI / ORCHESTRATION TIER  
  \+---------------------------------------------------------------------------------------+  
  |  Ubuntu Mini PC (CI Controller)                                                       |  
  |                                                                                       |  
  |  \+--------------------+      \+-----------------------+      \+----------------------+  |  
  |  |  Jenkins (DooD)    | \---\> | Sonatype Nexus OSS    | \---\> | SonarQube Scanner    |  |  
  |  |  \- Pipeline-as-Code|      | \- Hosted NuGet (Lock) |      | \- Static Analysis    |  |  
  |  |  \- Trivy Scanner   |      | \- Private OCI (Docker)|      | \- Quality Gate Wait  |  |  
  |  \+--------------------+      \+-----------------------+      \+----------------------+  |  
  |            |                                                                          |  
  |            v                                                                          |  
  |  \+---------------------------------------------------------------------------------+  |  
  |  |  Ansible Automation Engine (Dockerized Runner)                                  |  |  
  |  |  \- SSH-Key Injection (Ephemeral) | In-Memory Vault Secret Decryption            |  |  
  |  \+---------------------------------------------------------------------------------+  |  
  \+------------------------------------------+--------------------------------------------+  
                                             | SSH (Port 22\)  
                                             v  
                             SYSTEMS INTEGRATION LAB (SIL) TIER  
  \+---------------------------------------------------------------------------------------+  
  |  Raspberry Pi 400 (Debian ARM64 \- Embedded Node Target)                               |  
  |                                                                                       |  
  |                     \+---------------------------------------+                         |  
  |                     |  NGINX Reverse Proxy (mc-proxy)       | \<== Ingress: Port 8085  |  
  |                     |  \- Upstream: 172.17.0.1:5001 / 5002   |                         |  
  |                     \+---------------------------------------+                         |  
  |                                      |      ^                                         |  
  |                     \+----------------+      \+---------------+                         |  
  |                     v                                       v                         |  
  |  \+-------------------------------------+   \+-------------------------------------+    |  
  |  | \[Slot: Blue\] mc-blue                |   | \[Slot: Green\] mc-green              |    |  
  |  | \- Port: 5001 \-\> Container 8080      |   | \- Port: 5002 \-\> Container 8080      |    |  
  |  | \- .NET 8 Web API (Chiseled Runtime) |   | \- .NET 8 Web API (Chiseled Runtime) |    |  
  |  | \- Device: /dev/i2c-1, /dev/gpiomem  |   | \- Device: /dev/i2c-1, /dev/gpiomem  |    |  
  |  \+-------------------------------------+   \+-------------------------------------+    |  
  |                                                                                       |  
  |  \+---------------------------------------------------------------------------------+  |  
  |  |  Host Supervision: sil-watchdog.service                                         |  |  
  |  |  \- Local Health Evaluation (127.0.0.1:8085/health)                              |  |  
  |  |  \- Autonomous Rollback & 503 Quarantine Execution                              |  |  
  |  \+---------------------------------------------------------------------------------+  |  
  \+---------------------------------------------------------------------------------------+

## **3\. Hardware-in-the-Loop (HIL) Testbed Topology**

| Node Identifier | Hardware & OS | Operational Role | Key Software Components |
| :---- | :---- | :---- | :---- |
| **homelab-dev** | Lenovo ThinkPad (WSL2 Ubuntu 24.04) | Workstation & Out-of-Band Admin | Git, VS Code, Ansible Core, SSH |
| **homelab-node1** | Mini PC (AMD Ryzen 7, 32GB RAM, Ubuntu) | CI Controller & Registry Store | Jenkins (DooD), Sonatype Nexus OSS, Docker Engine\[cite: 4, 5\] |
| **sil-agent-01** | Raspberry Pi 400 (4GB RAM, Broadcom ARM64) | SIL Edge Integration Target | Docker Engine, NGINX 1.27, Broadcom I2C bus\[cite: 4, 5\] |
| **sil-isolated** | Raspberry Pi 3B (1GB RAM, Debian) | Air-Gap Staging Simulation | Local boundary validation, transfer simulation\[cite: 4, 5\] |

## **4\. DevSecOps & Supply Chain Governance**

### **Solution-Wide Deterministic Configuration (Directory.Build.props)**

XML  
\<Project\>  
  \<PropertyGroup\>  
    \<Nullable\>enable\</Nullable\>  
    \<ImplicitUsings\>enable\</ImplicitUsings\>  
    \<TreatWarningsAsErrors\>true\</TreatWarningsAsErrors\>  
    \<Deterministic\>true\</Deterministic\>  
    \<RestoreLockedMode\>true\</RestoreLockedMode\>  
    \<ContinuousIntegrationBuild\>true\</ContinuousIntegrationBuild\>  
  \</PropertyGroup\>  
\</Project\>

### **Air-Gapped Package Source Mapping (nuget.config)**

XML  
\<?xml version="1.0" encoding="utf-8"?\>  
\<configuration\>  
  \<packageSources\>  
    \<clear /\>  
    \<add key\="nexus-hosted-nuget" value\="http\://10.0.0.182:8081/repository/nuget-hosted/index.json" /\>  
  \</packageSources\>  
  \<packageSourceMapping\>  
    \<packageSource key\="nexus-hosted-nuget"\>  
      \<package pattern\="\*" /\>  
    \</packageSource\>  
  \</packageSourceMapping\>  
\</configuration\>

### **Hardened Distroless Packaging (Dockerfile)**

Dockerfile  
\# Stage 1: Build & Publish  
FROM mcr.microsoft.com/dotnet/sdk:8.0\-jammy AS build  
WORKDIR /src

COPY Directory.Build.props nuget.config ./  
COPY src/MissionControl.Api/MissionControl.Api.csproj src/MissionControl.Api/  
COPY src/MissionControl.Api/packages.lock.json src/MissionControl.Api/

RUN dotnet restore src/MissionControl.Api/MissionControl.Api.csproj \\  
    \--configfile nuget.config \\  
    \--locked-mode

COPY src/MissionControl.Api/ src/MissionControl.Api/  
WORKDIR /src/src/MissionControl.Api  
RUN dotnet publish MissionControl.Api.csproj \\  
    \-c Release \\  
    \--no-restore \\  
    \-o /app/publish \\  
    /p:ContinuousIntegrationBuild=true \\  
    /p:UseAppHost=false

\# Stage 2: Distroless Hardened Runtime (Ubuntu Chiseled)  
FROM mcr.microsoft.com/dotnet/aspnet:8.0\-jammy-chiseled AS final  
WORKDIR /app

USER \$APP\_UID

COPY \--from=build \--chown=\$APP\_UID:\$APP\_UID /app/publish .

ENV ASPNETCORE\_HTTP\_PORTS=8080 \\  
    DOTNET\_EnableDiagnostics=0 \\  
    DOTNET\_CLI\_TELEMETRY\_OPTOUT=1

EXPOSE 8080  
ENTRYPOINT \["dotnet", "MissionControl.Api.dll"\]

## **5\. Blue/Green Zero-Downtime Deployment Engine**

### **Dynamic Slot Topology Calculation (ansible/roles/blue\_green/tasks/main.yml)**

YAML  
\# \==============================================================================  
\# PHASE 1: DISCOVERY & QUARANTINE RECOVERY  
\# \==============================================================================  
\- name: Read current active deployment slot from baseline file  
  ansible.builtin.slurp:  
    src: "{{ app\_base\_dir }}/active\_slot"  
  register: active\_slot\_raw

\- name: Normalize active slot state and detect quarantine  
  ansible.builtin.set\_fact:  
    raw\_slot: "{{ active\_slot\_raw.content | b64decode | trim }}"

\- name: Evaluate deployment recovery posture  
  ansible.builtin.set\_fact:  
    is\_quarantined: "{{ raw\_slot not in \['blue', 'green'\] }}"  
    current\_slot: "{{ 'none' if (raw\_slot not in \['blue', 'green'\]) else raw\_slot }}"  
    target\_slot: "{{ 'blue' if (raw\_slot not in \['blue', 'green'\]) else ('green' if raw\_slot \== 'blue' else 'blue') }}"

\- name: Set dynamic slot port mappings safely  
  ansible.builtin.set\_fact:  
    current\_port: "{{ slots\[current\_slot\].port if not is\_quarantined else 0 }}"  
    target\_port: "{{ slots\[target\_slot\].port }}"

\- name: Inspect Docker bridge network to dynamically resolve Gateway IP  
  community.docker.docker\_network\_info:  
    name: bridge  
  register: docker\_bridge\_info

\- name: Assign dynamic Docker gateway IP  
  ansible.builtin.set\_fact:  
    docker\_gw\_ip: "{{ docker\_bridge\_info.network.IPAM.Config\[0\].Gateway }}"

### **Ingress Upstream Template (gateway.conf.j2)**

Nginx  
upstream mission\_control\_backend {  
    server {{ docker\_gw\_ip }}:{{ target\_port }} max\_fails=3 fail\_timeout=5s;  
    keepalive 32;  
}

server {  
    listen {{ ingress\_port }} default\_server;  
    server\_name \_;

    proxy\_connect\_timeout 2s;  
    proxy\_read\_timeout 5s;  
    proxy\_send\_timeout 2s;

    location /health {  
        proxy\_pass http\://mission\_control\_backend;  
        proxy\_http\_version 1.1;  
        proxy\_set\_header Connection "";  
        proxy\_set\_header Host \$host;  
        access\_log off;  
    }

    location / {  
        proxy\_pass http\://mission\_control\_backend;  
        proxy\_http\_version 1.1;  
        proxy\_set\_header Connection "";  
        proxy\_set\_header Host \$host;  
        proxy\_set\_header X-Real-IP \$remote\_addr;  
        proxy\_set\_header X-Forwarded-For \$proxy\_add\_x\_forwarded\_for;  
    }  
}

## **6\. Hardware-in-the-Loop (HIL) Pre-Flight Gating**

YAML  
\# \==============================================================================  
\# PHASE 0: HARDWARE-IN-THE-LOOP (HIL) SENSOR & HOST PRE-FLIGHT DIAGNOSTICS  
\# \==============================================================================  
\- name: Probe required hardware bus device nodes  
  ansible.builtin.stat:  
    path: "{{ item }}"  
  loop:  
    \- "/dev/i2c-1"  
    \- "/dev/gpiomem"  
  register: hil\_devices\_probe

\- name: Gate deployment on physical device node availability  
  ansible.builtin.assert:  
    that:  
      \- item.stat.exists  
    fail\_msg: "CRITICAL HIL FAILURE: Hardware device \[{{ item.item }}\] is not bound on the target node."  
    success\_msg: "Hardware device \[{{ item.item }}\] present and bound."  
  loop: "{{ hil\_devices\_probe.results }}"  
  loop\_control:  
    label: "{{ item.item }}"

\- name: Inspect target node disk capacity on deployment partition (/opt)  
  ansible.builtin.shell: "df \--output=avail \-k /opt | tail \-n 1"  
  register: opt\_avail\_kb  
  changed\_when: false  
  become: no

\- name: Gate deployment if target filesystem free space is below threshold (\< 1GB)  
  ansible.builtin.assert:  
    that:  
      \- (opt\_avail\_kb.stdout | trim | int) \>= 1048576  
    fail\_msg: "CRITICAL: Target node /opt partition has less than 1GB free (Available: {{ opt\_avail\_kb.stdout | trim }} KB)."  
    success\_msg: "Disk capacity verified: {{ (opt\_avail\_kb.stdout | trim | int / 1024\) | round(2) }} MB available on /opt."

\- name: Probe CPU thermal envelope on target embedded hardware (Broadcom/ARM/x86)  
  ansible.builtin.shell: |  
    if \[ \-f /sys/class/thermal/thermal\_zone0/temp \]; then  
      cat /sys/class/thermal/thermal\_zone0/temp  
    elif command \-v vcgencmd \>/dev/null 2\>&1; then  
      vcgencmd measure\_temp | grep \-o \-E '\[0-9.\]+' | awk '{print \$1 \* 1000}'  
    else  
      echo "45000"  
    fi  
  register: host\_temp\_raw  
  changed\_when: false  
  become: no

\- name: Gate deployment if node thermal limit is exceeded (\> 75°C)  
  ansible.builtin.assert:  
    that:  
      \- (host\_temp\_raw.stdout | trim | int) \<= 75000  
    fail\_msg: "CRITICAL: Thermal throttling danger\! Node temperature is {{ (host\_temp\_raw.stdout | trim | int / 1000\) | round(1) }}°C. Threshold is 75°C."  
    success\_msg: "Thermal envelope nominal: {{ (host\_temp\_raw.stdout | trim | int / 1000\) | round(1) }}°C."

## **7\. Autonomous Fail-Safe & Watchdog Engine**

### **Autonomous Node Watchdog (/opt/mission-control/bin/sil-watchdog.sh)**

Bash  
\#\!/usr/bin/env bash  
set \-euo pipefail

APP\_BASE="/opt/mission-control"  
ACTIVE\_SLOT\_FILE="\${APP\_BASE}/active\_slot"  
NGINX\_CONF="\${APP\_BASE}/nginx/conf.d/gateway.conf"  
PROBE\_URL="http\://127.0.0.1:8085/health"  
MAX\_FAILURES=3  
CHECK\_INTERVAL\_SEC=5  
TRIAGE\_DIR="\${APP\_BASE}/triage"

PORT\_blue=5001  
PORT\_green=5002

log() {  
    echo "\[\$(date \-u \+'%Y-%m-%dT%H:%M:%SZ')\] \[WATCHDOG\] \$\*"  
}

engage\_critical\_stop() {  
    local incident\_dir="\${TRIAGE\_DIR}/watchdog-doublefault-\$(date \+%s)"  
    log "CRITICAL: Fallback slot failed readiness\! Engaging forensic fail-safe lockdown..."  
    mkdir \-p "\${incident\_dir}"

    docker logs \--tail 200 mc-blue \> "\${incident\_dir}/mc-blue.log" 2\>&1 || true  
    docker logs \--tail 200 mc-green \> "\${incident\_dir}/mc-green.log" 2\>&1 || true  
    docker logs \--tail 200 mc-proxy \> "\${incident\_dir}/mc-proxy.log" 2\>&1 || true  
    dmesg \-T | tail \-n 150 \> "\${incident\_dir}/dmesg.log" 2\>&1 || true  
    ss \-tlpn \> "\${incident\_dir}/sockets.log" 2\>&1 || true

    cat \<\< 'NGINX\_FAIL' \> "\${NGINX\_CONF}"  
server {  
    listen 8085 default\_server;  
    server\_name \_;

    location / {  
        default\_type application/json;  
        add\_header Retry-After 300 always;  
        return 503 '{"status":"CRITICAL\_STOP","error":"SIL Node Quarantined by Local Watchdog. Both application slots degraded."}\\n';  
    }

    location /health {  
        default\_type text/plain;  
        return 503 'Maintenance Mode \- Watchdog Quarantined\\n';  
    }  
}  
NGINX\_FAIL

    docker exec mc-proxy nginx \-s reload || true  
    docker stop mc-blue mc-green 2\>/dev/null || true  
    echo "quarantined\_double\_fault" \> "\${ACTIVE\_SLOT\_FILE}"  
    exit 2  
}

trigger\_local\_rollback() {  
    local failed\_slot="\$1"  
    local fallback\_slot="green"  
    local fallback\_port=\${PORT\_green}

    if \[\[ "\${failed\_slot}" \== "green" \]\]; then  
        fallback\_slot="blue"  
        fallback\_port=\${PORT\_blue}  
    fi

    log "ALERT: Slot \[\${failed\_slot}\] degraded. Initiating autonomous rollback to \[\${fallback\_slot}\]..."

    docker start "mc-\${fallback\_slot}" || engage\_critical\_stop

    local ready=0  
    for attempt in {1..10}; do  
        if curl \-s \-f \--connect-timeout 2 \--max-time 3 "http\://127.0.0.1:\${fallback\_port}/health" \>/dev/null 2\>&1; then  
            ready=1  
            break  
        fi  
        sleep 1  
    done

    if \[\[ \${ready} \-ne 1 \]\]; then  
        log "ERROR: Standby container mc-\${fallback\_slot} failed internal readiness probe on port \${fallback\_port}."  
        engage\_critical\_stop  
    fi

    local docker\_gw  
    docker\_gw=\$(docker network inspect bridge \--format '{{(index .IPAM.Config 0).Gateway}}')

    cat \<\< NGINX\_CONF\_OUT \> "\${NGINX\_CONF}"  
upstream mission\_control\_backend {  
    server $docke{r}_{g}w:${fallback\_port} max\_fails=3 fail\_timeout=5s;  
    keepalive 32;  
}

server {  
    listen 8085 default\_server;  
    server\_name \_;

    proxy\_connect\_timeout 2s;  
    proxy\_read\_timeout 5s;  
    proxy\_send\_timeout 2s;

    location /health {  
        proxy\_pass http\://mission\_control\_backend;  
        proxy\_http\_version 1.1;  
        proxy\_set\_header Connection "";  
        proxy\_set\_header Host \\\$host;  
        access\_log off;  
    }

    location / {  
        proxy\_pass http\://mission\_control\_backend;  
        proxy\_http\_version 1.1;  
        proxy\_set\_header Connection "";  
        proxy\_set\_header Host \\\$host;  
        proxy\_set\_header X-Real-IP \\\$remote\_addr;  
        proxy\_set\_header X-Forwarded-For \\\$proxy\_add\_x\_forwarded\_for;  
    }  
}  
NGINX\_CONF\_OUT

    docker exec mc-proxy nginx \-t  
    docker exec mc-proxy nginx \-s reload

    echo "\${fallback\_slot}" \> "\${ACTIVE\_SLOT\_FILE}"  
    docker stop "mc-\${failed\_slot}" 2\>/dev/null || true  
    log "SUCCESS: Autonomous rollback completed. Slot \[\${fallback\_slot}\] is now active."  
}

consecutive\_failures=0  
log "Watchdog supervisor active on target node. Monitoring \${PROBE\_URL} every \${CHECK\_INTERVAL\_SEC}s..."

while true; do  
    if \[\[ \! \-f "\${ACTIVE\_SLOT\_FILE}" \]\]; then  
        sleep "\${CHECK\_INTERVAL\_SEC}"  
        continue  
    fi

    active\_slot=\$(cat "\${ACTIVE\_SLOT\_FILE}" | tr \-d '\[:space:\]')

    if \[\[ "\${active\_slot}" \== "quarantined\_double\_fault" \]\]; then  
        sleep "\${CHECK\_INTERVAL\_SEC}"  
        continue  
    fi

    if curl \-s \-f \--connect-timeout 2 \--max-time 4 "\${PROBE\_URL}" \> /dev/null 2\>&1; then  
        consecutive\_failures=0  
    else  
        consecutive\_failures=\$((consecutive\_failures \+ 1))  
        log "WARNING: Probe failed (\${consecutive\_failures}/\${MAX\_FAILURES}) for slot \[\${active\_slot}\]."

        if \[\[ \${consecutive\_failures} \-ge \${MAX\_FAILURES} \]\]; then  
            log "THRESHOLD EXCEEDED: Health checks failed consecutively."  
            trigger\_local\_rollback "\${active\_slot}"  
            consecutive\_failures=0  
        fi  
    fi

    sleep "\${CHECK\_INTERVAL\_SEC}"  
done

## **8\. Configuration Control & Audit Compliance**

### **Process-Table Secret Masking via Ansible Vault**

To prevent secrets from leaking into /proc/\<pid\>/cmdline or ps aux, secrets are committed encrypted via AES-256 in ansible/group\_vars/sil\_nodes/vault.yml\[cite: 4, 5\]:

YAML  
vault\_nexus\_user: \!vault |  
          \$ANSIBLE\_VAULT;1.1;AES256  
          31363632363737383232386161323832346633653139333939396365316434316134633333393433  
vault\_nexus\_pass: \!vault |  
          \$ANSIBLE\_VAULT;1.1;AES256  
          62386337633235313838383333363435343564613532653232313364376536343531353264666632

Secrets are passed strictly via \--vault-password-file referencing an ephemeral, user-restricted file (chmod 600\) trapped for secure shredding:

Bash  
shred \-u \-z \-v \-n 3 ./vault\_pass\_tmp

### **Jira Closed-Loop Audit Integration (Jenkinsfile)**

Bash  
AUTH\_B64=\$(printf "%s:%s" "\${JIRA\_USER}" "\${JIRA\_TOKEN}" | base64 | tr \-d '\\n')  
CURL\_CONF=\$(mktemp)  
chmod 600 "\${CURL\_CONF}"  
echo "header \= \\"Authorization: Basic \${AUTH\_B64}\\"" \> "\${CURL\_CONF}"  
trap 'rm \-f "\${CURL\_CONF}"' EXIT INT TERM

curl \-s \-f \-X POST \\  
  \-K "\${CURL\_CONF}" \\  
  \-H "Accept: application/json" \\  
  \-H "Content-Type: application/json" \\  
  \-d "{\\"body\\": \\"BASELINE DEPLOYMENT HALTED: Build \[\#\${BUILD\_NUMBER}\] failed smoke test. SIL node placed in Fail-Safe Lock.\\"}" \\  
  "\${JIRA\_API\_ENDPOINT}/\${JIRA\_KEY}/comment"

## **9\. Verification & Validation Runbook**

### **Clean Automated Pipeline Run**

Bash  
\# Trigger Jenkins pipeline via Webhook or CLI  
\# Parameters:  
\#   BUILD\_SCAN\_TEST\_ENABLE  \= true  
\#   RUN\_IMAGE\_VULN\_SCAN     \= true  
\#   TARGET\_TAG              \= 50-b5b1f1e

### **Simulating Automated Ingress Rollback**

Bash  
\# 1\. Update Jenkinsfile Stage 7 to probe a deliberately failing path:  
curl \--fail \--retry 3 \--retry-delay 2 \--max-time 5 http\://10.0.0.163:8085/healthx

\# 2\. Pipeline catches error code 22, runs ansible/rollback.yml,  
\# restores fallback slot, reloads NGINX, and marks build UNSTABLE.

### **Simulating Double-Fault Node Quarantine**

Bash  
\# 1\. Sabotage standby container mc-green on target node:  
docker rm \-f mc-green && docker run \-d \--name mc-green alpine sleep 3600

\# 2\. Terminate active container mc-blue:  
docker stop mc-blue

\# 3\. Watchdog or Pipeline catches double failure, runs fail\_safe.yml,  
\# deploys 503 Maintenance Ingress, and logs dumps to /opt/mission-control/triage/.

## **10\. Engineering Standards & Methodologies**

* **Configuration Management:** IEEE 828-2012 / EIA-649 Standards for Configuration Baselines\[cite: 4, 5\].  
* **Static Code Analysis:** SonarQube Clean Architecture / Roslyn Code Analysis Rules (CA1861, CA1852)\[cite: 4, 5\].  
* **Container Security:** CIS Docker Benchmark & NIST SP 800-190 Container Security Guidelines\[cite: 4, 5\].  
* **Infrastructure as Code:** Idempotent Ansible Core Collections (community.docker, ansible.posix).

> 
