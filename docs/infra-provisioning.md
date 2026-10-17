# Infrastructure Provisioning Runbook: CI/CD Control Plane
**Target Host:** Ubuntu Mini PC (`homelab-node1` | 10.0.0.182)  
**Standard:** Controlled Goods Program (CGP) & IEEE 828 Configuration Management  
**Architecture:** Containerized Control Plane with Docker-out-of-Docker (DooD) Execution

---

## 1. Scope & Architectural Overview

This document details the Day-0 configuration and automated deployment of the mission-critical CI/CD Control Plane. The control plane hosts three foundational systems in isolated Docker execution namespaces:
* **CI/CD Controller:** Jenkins LTS with DooD access over `/var/run/docker.sock` to dynamically spawn ephemeral .NET 10 compilation, SAST scanning, and Ansible deployment containers.
* **Artifact Hub:** Sonatype Nexus OSS hosting private OCI Docker registries (port `8082`), internal NuGet feeds (port `8081`), and raw binary stores.
* **Static Code Analysis (SAST):** SonarQube Community backed by PostgreSQL 15, enforcing quality gates and Roslyn analysis prior to artifact signing.

---

## 2. Host Prerequisites & Linux Kernel Hardening

Run these commands on the Ubuntu Mini PC (`chand@10.0.0.182`) to satisfy virtual memory limits for ElasticSearch (SonarQube) and establish persistent network endpoints.

### Virtual Memory & Max Map Count (Sysctl)
SonarQube's embedded search node requires an elevated `mmap` count. Configure this permanently:

```bash
# Set runtime parameter
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072

# Persist across reboots
sudo tee /etc/sysctl.d/99-sonarqube-limits.conf << 'EOF'
vm.max_map_count=524288
fs.file-max=131072
EOF
```

### Static Host DNS Aliases (/etc/hosts)
To decouple pipeline configurations from static IP addresses, define FQDN aliases locally on the Mini PC:

```bash
sudo tee -a /etc/hosts << 'EOF'
10.0.0.182  nexus.homelab.local
10.0.0.182  sonar.homelab.local
10.0.0.163  sil-target.homelab.local
EOF
```

### Docker Daemon Trust Configuration (/etc/docker/daemon.json)
Nexus terminates the local OCI registry on port 8082 over HTTP within the internal laboratory perimeter. Instruct the local Docker daemon to trust this endpoint without prompting for TLS:
```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "insecure-registries": ["nexus.homelab.local:8082", "10.0.0.182:8082"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
```
## 3. Directory Layout & POSIX Permission Enforcement
Defence-grade operations require strict separation of concerns. Compute data must be owned by designated system UIDs rather than standard user accounts.
```bash
# 1. Create directory structure
sudo mkdir -p /opt/nexus-data
sudo mkdir -p /opt/sonarqube/{data,extensions,logs,db}
sudo mkdir -p /var/jenkins_home
sudo mkdir -p /opt/infra-control-plane

# 2. Extract Docker group ID on the host
DOCKER_GID=$(getent group docker | cut -d: -f3)

# 3. Apply exact UID/GID ownership
# Nexus standard UID: 200
sudo chown -R 200:200 /opt/nexus-data

# SonarQube standard UID: 1000
sudo chown -R 1000:1000 /opt/sonarqube

# Jenkins controller UID: 1000, mapped to host Docker group
sudo chown -R 1000:${DOCKER_GID} /var/jenkins_home

# 4. Enforce POSIX directory security
sudo chmod -R 770 /opt/nexus-data
sudo chmod -R 770 /opt/sonarqube
sudo chmod -R 775 /var/jenkins_home
```
## 4. Control Plane Deployment Execution
Place the verified docker-compose.yml into /opt/infra-control-plane/docker-compose.yml:

```Bash
cd /opt/infra-control-plane

# Launch the entire control plane stack in detached mode
docker compose up -d
Verification & Health State Audit
Verify that all four containers initialize and pass their respective health probes:
```

```Bash
docker compose ps
```
Expected output:
```
NAME                IMAGE                     COMMAND                  SERVICE      CREATED         STATUS                   PORTS
jenkins-controller  jenkins/jenkins:lts-jdk17 "/usr/bin/tini -- /usr…" jenkins      2 minutes ago   Up 2 minutes (healthy)   0.0.0.0:8080->8080/tcp, 0.0.0.0:50000->50000/tcp
nexus-controller    sonatype/nexus3:3.70.1    "/opt/sonatype/nexus…"   nexus        2 minutes ago   Up 2 minutes (healthy)   0.0.0.0:8081-8082->8081-8082/tcp
sonarqube-db        postgres:15-alpine        "docker-entrypoint.s…"   sonar-db     2 minutes ago   Up 2 minutes (healthy)   5432/tcp
sonarqube-server    sonarqube:10.6-community  "/opt/sonarqube/bin/…"   sonarqube    2 minutes ago   Up 2 minutes (healthy)   0.0.0.0:9000->9000/tcp
```
## 5. First-Boot System Configuration & Baseline Setup
### 1. Sonatype Nexus OSS Baseline (Port 8081)
#### Step 1: Retrieve initial admin password:
```bash
sudo cat /opt/nexus-data/admin.password
```
#### Step 2: Navigate to http://10.0.0.182:8081 and complete setup:

Disable anonymous access.
##### Create OCI Docker Registry:
    Type: docker (hosted)
    Name: docker-hosted
    HTTP Connector Port: 8082
    Enable Docker V1 API: Disabled (v2 only).
##### Create NuGet Proxy/Hosted Repositories:
    Create nuget-hosted (Internal packages).
    Create nuget-group (Exposing http://10.0.0.182:8081/repository/nuget-group/index.json).
##### Create Raw Artifact Store:
    Type: raw (hosted)
    Name: raw-hosted

### 2. SonarQube Baseline (Port 9000)
    Log in to http://10.0.0.182:9000 (admin / admin).
    Update default credentials.
    Navigate to Administration > Security > Users > Tokens.
    Generate a Global Analysis Token named jenkins-sonar-token.
    Store this token in Jenkins Credentials Store as Secret Text (sonar-token).

### 3. Jenkins DooD Controller (Port 8080)
Step 1: Retrieve initial unlock key:
```
sudo cat /var/jenkins_home/secrets/initialAdminPassword
```
Step2: Complete setup and install suggested plugins plus:
```
Pipeline: Multibranch
Docker Pipeline
SSH Agent
SonarQube Scanner
```
Step 3: Verify DooD permissions by running a test job executing sh 'docker ps'

## 6. Systemd Auto-Recovery Unit
To ensure the control plane recovers automatically across host power failures or scheduled maintenance cycles, bind the Compose stack to a systemd supervisor daemon:
```
sudo tee /etc/systemd/system/defence-control-plane.service << 'EOF'
[Unit]
Description=Mission-Control CI/CD Infrastructure Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/infra-control-plane
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable defence-control-plane.service
```