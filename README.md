# Defence DevOps Engineering Mentor & Interview Coach
## Client Mandate: Leonardo DRS (Kanata, ON) | C# / .NET Mission-Critical Systems

---

## 1. Mandate Dossier & Context
* **Role Title:** DevOps Engineer – C# / .NET (Contract)
* **Engagement Duration:** 6–9 Month Initial Contract (High probability of extension / permanent conversion)
* **Client / End-User:** Leonardo DRS (Kanata, ON) via TAS Techno | Aero | Services (Paul-Émile Mesplède)[cite: 3, 4]
* **Domain:** Regulated Defence, Naval Sensor Systems, EW/C2, Controlled Goods Program (CGP), Reliability/Secret Clearance
* **Rate Target:** $85.00 – $95.00+ CAD/hr incorporated B2B (OpsTime Labs Inc.)
* **Candidate Clearance Posture:**
  * Canadian Citizen, continuous Canadian residency since August 2019 (7+ years).
  * Documented prior US residency (2015–2019) with a clean Five Eyes trace.
  * Immediate eligibility for Controlled Goods Program (CGP) and TBS 330-23 / 330-60 screening.

---

## 2. Technical Stack & Architecture Mapping

| Mandate Pillar | Production Implementation (Homelab Mirror) |
| :--- | :--- |
| **C# / .NET SDK & MSBuild[cite: 4, 5]** | .NET 8 SDK, solution-level `Directory.Build.props`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, `<Deterministic>true</Deterministic>`, locked dependencies via `packages.lock.json` (`dotnet restore --locked-mode`). |
| **Air-Gapped Feeds[cite: 4, 5]** | Sonatype Nexus OSS hosting private authenticated NuGet proxies and OCI Docker registries; zero direct internet access during builds. |
| **Linux Containerization[cite: 4, 5]** | Multi-stage Docker builds deploying to **Ubuntu Chiseled** (`aspnet:8.0-jammy-chiseled`), non-root `$APP_UID`, zero package managers, and no interactive shell (`/bin/sh`). |
| **DevSecOps & Gating[cite: 4, 5]** | Static code analysis via SonarQube with quality gates (`sonar.qualitygate.wait=true`), CVE scanning via Aquasec Trivy (`--exit-code 1` on `HIGH`/`CRITICAL`). |
| **Controlled Delivery[cite: 4, 5]** | Declarative `Jenkinsfile` (DooD), Ansible blue/green deployment orchestration (`mc-blue` on port 5001, `mc-green` on port 5002), atomic NGINX upstream cutover on port 8085. |
| **Fault Recovery & HIL[cite: 4, 5]** | Multi-tier recovery ladder: Ansible single-slot rollback, double-fault quarantine lock (HTTP 503 maintenance mode with `Retry-After: 300`), local autonomous node watchdog (`sil-watchdog.service`), and hardware-in-the-loop pre-flight device gating (`/dev/i2c-1`, `/dev/gpiomem`). |
| **Audit Traceability[cite: 4, 5]** | Automated Jira REST integration (`DRS-12`) annotating commits, build status, smoke test results, and forensic quarantine triggers. |

---

## 3. Physical Homelab Architecture

```text
[ ThinkPad Workstation ] ──(WSL2 Ubuntu)──> Dev / Git / Out-of-Band Host Provisioning (provision_sil.yml)
           │
           ▼
[ Ubuntu Mini PC ] ───────(CI Controller)─> Jenkins DooD, Sonatype Nexus OSS, SonarQube, Jira Integration
           │
           ▼ (SSH / OCI Pull)
[ Raspberry Pi 400 ] ─────(SIL Node Target)─> NGINX Proxy (8085), Blue/Green Slots (5001/5002), Hardware Bus (I2C/GPIO)
           │
[ Raspberry Pi 3B ] ──────(Bastion Node)───> Air-Gap / Bastion Transfer Simulation