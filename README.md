# agent-gitops-quickstarts

> AI-augmented GitOps Day 2 configuration for any OpenShift cluster —
> bare-metal, KVM, AWS, GCP, Azure, vSphere, Equinix, SNO, and beyond.

[![OpenShift](https://img.shields.io/badge/OpenShift-4.9%E2%80%934.22%20%7C%205.0-red)](https://docs.redhat.com/en/documentation/openshift_container_platform)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](LICENSE)
[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-orange)](https://argo-cd.readthedocs.io)

**[📖 End-to-End Guide](docs/end-to-end-guide.md)** · **[🤖 AI Skills](gitops/skills/README.md)** · **[📋 Full Reference](llm.txt)**

---

## What This Is

**agent-gitops-quickstarts** is the Day 2 counterpart to [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install).
Once your cluster is provisioned (Day 1), use this repo to configure it with operators,
storage, and workloads via ArgoCD + Kustomize.

```
openshift-agent-install  →  agent-gitops-quickstarts
  (provision cluster)         (configure + operate cluster)
        Day 1                        Day 2+
```

**Supported OCP versions:** 4.9 through 4.22 and 5.0 — operator overlays exist for every minor version.

**Supported platforms:** bare-metal · KVM/libvirt · AWS · GCP · Azure · VMware vSphere · Equinix Metal · Red Hat Labs

---

## Quick Start

### 1. Point to your Git repository

All ArgoCD Application YAMLs reference the repo URL. If you're using a fork, Gitea, or GitLab:

```bash
# Preview what changes:
./gitops/configure-repo.sh --dry-run https://your-repo-url.git

# Apply it (updates 111 YAML files):
./gitops/configure-repo.sh https://your-repo-url.git
git push <your-remote> main
```

Need a self-hosted Git server on OpenShift (air-gapped)?

```bash
./gitops/setup-gitea.sh   # auto-deploys Gitea + pushes repo + reconfigures URLs
```

### 2. Bootstrap ArgoCD

```bash
oc login https://api.<cluster>.<domain>:6443
cd gitops && ./deploy.sh
```

### 3. Deploy a cluster profile

```bash
oc apply -f gitops/apps/<profile>/cluster-config.yaml
```

ArgoCD creates per-operator Applications and syncs everything from Git.

---

## Cluster Profiles

| Profile | Platform | Use Case |
|---|---|---|
| `sno-ocp-virt` | Any (SNO) | SNO + OpenShift Virtualization |
| `standard-sno-deployment` | Any (SNO) | SNO + ODF storage + Pipelines |
| `kvm-ocp-virt` | KVM/libvirt | KVM VMs + ODF + Virtualization |
| `aws-odf-deployment` | AWS | AWS cluster + ODF (gp2 EBS) |
| `gcp-odf-deployment` | GCP | GCP cluster + ODF (Persistent Disk) |
| `vmware-odf-deployment` | vSphere | VMware + ODF |
| `equinix-cnv-virtualization` | Equinix Metal | Bare-metal + Virtualization |
| `equinix-developer-env` | Equinix Metal | Bare-metal developer environment |
| `acm-gitops-deployment` | Any | RHACM hub cluster |
| `aap-instance` | Any | Ansible Automation Platform |
| `developer-env` | Any | Dev tools: AAP + Dev Spaces |
| `baremetal-rhacm-hub` | Bare-metal | Full bare-metal hub: RHACM + AAP |
| `device-edge-demos` | Any | Device Edge + Quay |
| `kafka-plus-db` | Any | Kafka + PostgreSQL |
| `middleware-ocpv` | Any | Middleware + OCP Virt |
| `rhel-edge-management` | Any | RHEL Edge management |

---

## Multi-Node Lab / KVM Setup

For bare-metal, KVM, or Red Hat Labs clusters with 3+ worker nodes:

```bash
# Dry-run preview (see what would happen):
./gitops/configure-redhat-labs.sh --dry-run --configure-storage

# Full setup with auto-node-discovery and self-learning:
./gitops/configure-redhat-labs.sh \
  --configure-infra-nodes \
  --configure-storage \
  --profile kvm-ocp-virt \
  --learn

# Explicit nodes + OCP version:
./gitops/configure-redhat-labs.sh \
  --nodes worker-0,worker-1,worker-2 \
  --ocp-version 4.22 \
  --configure-infra-nodes \
  --configure-storage \
  --learn
```

The `--learn` flag writes an execution journal that an AI agent reads to automatically
improve skills, overlays, and profiles for new environment types. See [Self-Learning](#self-learning).

---

## AI Skills

> Full skills documentation: **[gitops/skills/README.md](gitops/skills/README.md)**

Install skills for use with Claude Code (or any agentskills.io-compatible agent):

```bash
./gitops/skills/install-skills.sh --list     # list all 9 skills
./gitops/skills/install-skills.sh --all      # install all skills
./gitops/skills/install-skills.sh --skill bootstrap-gitops
```

Once installed, trigger skills in Claude Code with natural language — for example:
- *"bootstrap gitops on my cluster"*
- *"install ODF on OCP 4.22"*
- *"configure lab environment with nodes worker-0,worker-1,worker-2"*
- *"ArgoCD not syncing — help me troubleshoot"*

| Skill | Description |
|---|---|
| `bootstrap-gitops` | Bootstrap ArgoCD on a fresh cluster |
| `install-odf` | Install OpenShift Data Foundation (ODF/Ceph) |
| `install-virtualization` | Install OpenShift Virtualization (CNV/KubeVirt) |
| `install-acm` | Install Red Hat Advanced Cluster Management hub |
| `configure-ztp` | Configure ZTP spoke cluster provisioning |
| `install-aap` | Install Ansible Automation Platform |
| `deploy-profile` | Deploy a full cluster profile via ArgoCD |
| `troubleshoot-argocd` | Diagnose and fix ArgoCD sync failures |
| `configure-lab-environment` | Configure infra nodes + local storage + ODF + profile on any multi-node cluster |

Pull community Red Hat agentic skills:

```bash
./gitops/skills/pull-rh-skills.sh
```

---

## Self-Learning

The repository gets smarter with every new cluster type it configures:

```
configure-redhat-labs.sh --learn
        ↓
writes gitops/learnings/<timestamp>.yaml   ← sanitized, safe to commit
writes gitops/learnings/<timestamp>.raw.yaml ← full data, gitignored (stays local)
        ↓
Claude Code: "review the latest learning at gitops/learnings/ and update skills"
        ↓
learn-environment agent:
  SUCCESS → creates new overlays, profiles, wrapper scripts, updates skill Known Working Configs
  FAILURE → adds failure modes to configure-lab-environment/SKILL.md
```

### Data safety

Sensitive data (cluster domains, node FQDNs, internal names) is **automatically scrubbed**
before anything reaches git:

```bash
# Sanitize a journal manually:
./gitops/sanitize-journal.sh gitops/learnings/my.raw.yaml gitops/learnings/my.yaml

# Install pre-commit hook that blocks sensitive data automatically:
./gitops/setup-git-hooks.sh
```

---

## Operator Coverage

OCP version overlays for every operator — 4.9 through 4.22 and 5.0:

| Operator | Channels available |
|---|---|
| OpenShift Data Foundation | stable-4.9 → stable-4.22, stable-5.0 |
| ODF LVM Operator | stable-4.11 → stable-4.22 |
| Local Storage Operator | stable-4.9 → stable-4.22, stable-5.0 |
| OpenShift Virtualization | stable |
| OpenShift Pipelines | latest, latest-5.0 |
| RHACM | release-2.x, stable-5.0 |

For the full operator catalog (24 operators), see [`llm.txt`](llm.txt).

---

## Repository Structure

```
agent-gitops-quickstarts/
  gitops/
    deploy.sh                    # Step 1: bootstrap ArgoCD
    configure-repo.sh            # Step 0: point to your Git repo (fork/Gitea/GitLab)
    configure-redhat-labs.sh     # Multi-node lab/KVM orchestrator with self-learning
    setup-gitea.sh               # Deploy self-hosted Gitea on OpenShift
    setup-git-hooks.sh           # Install pre-commit data safety hook
    sanitize-journal.sh          # Scrub sensitive data from learning journals
    apps/                        # Profile entry-points (16 profiles)
    cluster-config/              # Operator manifests (Kustomize bases + overlays)
    skills/                      # AI skill definitions (9 SKILL.md files)
    learnings/                   # Self-learning execution journals
  llm.txt                        # Complete AI reference for this repo
  AGENTS.md                      # Universal agent guardrails
  CLAUDE.md                      # Claude Code project instructions
```

---

## Prerequisites

- OpenShift cluster 4.9+ (any platform)
- `oc` CLI authenticated with cluster-admin
- For multi-node storage: 3+ worker nodes with local disks

Provision clusters with:
- [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install) (bare-metal / KVM / cloud)
- [Red Hat Assisted Installer](https://console.redhat.com/openshift/assisted-installer/clusters)

---

## Links

- [OpenShift GitOps (ArgoCD)](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops)
- [OpenShift Data Foundation](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation)
- [Red Hat ACM](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes)
- [gitops-catalog](https://github.com/redhat-cop/gitops-catalog)
- [agentskills.io](https://agentskills.io)
