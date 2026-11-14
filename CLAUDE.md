# CLAUDE.md — sno-quickstarts (migration in progress)

This repository is being refactored into **agent-gitops-quickstarts** — a broader,
AI-augmented GitOps quickstarts library for Day 2 OpenShift configuration.

## Migration Plan

See `.claude/migration-plan.md` for the full work breakdown.

## Current State

This repo provides GitOps-driven post-install configuration for OpenShift clusters
using ArgoCD + Kustomize. It is the logical Day 2 continuation of:
**https://github.com/tosin2013/openshift-agent-install** (Day 1 provisioning)

## Quick Start (current)

```bash
# 1. Login to your OpenShift cluster
oc login https://api.<cluster>.<domain>:6443

# 2. Bootstrap OpenShift GitOps (ArgoCD)
./gitops/deploy.sh

# 3. Apply a cluster profile
oc apply -f gitops/apps/<profile>/cluster-config.yaml
```

## Available Profiles

| Profile | Description |
|---------|-------------|
| `sno-ocp-virt` | SNO + OpenShift Virtualization |
| `standard-sno-deployment` | SNO + ODF + Pipelines |
| `acm-gitops-deployment` | RHACM hub setup |
| `aap-instance` | Ansible Automation Platform |
| `developer-env` | Dev tools stack |
| `vmware-odf-deployment` | VMware + ODF |
| `baremetal-rhacm-hub` | Bare metal RHACM hub |

## Skills (coming soon)

AI skills are being added in `gitops/skills/`. When complete, run:

```bash
./gitops/skills/install-skills.sh --all
```

## When in Doubt

Read `.claude/migration-plan.md` — it has the complete context and work breakdown.
