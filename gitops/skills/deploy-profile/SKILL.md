---
name: deploy-profile
description: Deploy a full cluster profile (app-of-apps) via ArgoCD to configure a cluster
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc"]
triggers:
  - "deploy profile"
  - "configure cluster"
  - "apply profile"
  - "deploy sno-ocp-virt"
  - "set up cluster profile"
  - "configure day 2"
---

# deploy-profile

## Overview

Deploys a complete cluster configuration profile using the app-of-apps pattern. Each profile
is an ArgoCD Application that points to a set of operator Applications, which in turn sync
all required manifests from the repository.

A profile encodes the full set of Day 2 operators for a specific cluster use case
(e.g., SNO with Virtualization, bare-metal RHACM hub, developer environment).

## Prerequisites

- ArgoCD bootstrapped: [[bootstrap-gitops]] completed
- Cluster meets resource requirements for the chosen profile

## Quick Diagnostics

```bash
# Check ArgoCD is running
oc get pods -n openshift-gitops | grep -v Running | grep -v Completed

# List all deployed Applications
oc get application -n openshift-gitops

# Check overall sync/health status
oc get application -n openshift-gitops -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'

# Get ArgoCD route for console access
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

## Available Profiles

| Profile | Platform | Use Case | Resource Requirements |
|---|---|---|---|
| `sno-ocp-virt` | Any (SNO) | SNO + Virtualization | 1 node, 32Gi RAM, NVMe disk |
| `standard-sno-deployment` | Any (SNO) | SNO + ODF + Pipelines | 1 node, 32Gi RAM, 3 disks |
| `kvm-ocp-virt` | KVM/libvirt | KVM VMs + ODF + Virtualization | 3+ VMs, 32Gi RAM, local disks |
| `aws-odf-deployment` | AWS | AWS cluster + ODF (gp2) | 3+ nodes, 32Gi RAM |
| `gcp-odf-deployment` | GCP | GCP cluster + ODF | 3+ nodes, 32Gi RAM |
| `vmware-odf-deployment` | vSphere | VMware + ODF | vSphere cluster, 3+ nodes |
| `equinix-cnv-virtualization` | Equinix Metal | Bare-metal + Virtualization | Equinix bare-metal nodes |
| `equinix-developer-env` | Equinix Metal | Bare-metal developer env | Equinix bare-metal nodes |
| `acm-gitops-deployment` | Any | RHACM hub | 3+ nodes, 32Gi RAM |
| `aap-instance` | Any | Ansible Automation Platform | 3+ nodes, 32Gi RAM |
| `developer-env` | Any | Dev tools (AAP + Dev Spaces) | 3+ nodes, 32Gi RAM |
| `baremetal-rhacm-hub` | Bare-metal | Full bare-metal hub | 3+ nodes, 64Gi RAM |
| `device-edge-demos` | Any | Device Edge + Quay | 3+ nodes |
| `kafka-plus-db` | Any | Kafka + PostgreSQL | 3+ nodes |
| `middleware-ocpv` | Any | Middleware + Virt | 3+ nodes |
| `rhel-edge-management` | Any | RHEL Edge management | 1 node |

## Steps

### Step 1: Review the profile definition

```bash
cat gitops/apps/<profile-name>/cluster-config.yaml
```

This shows the ArgoCD Application that points to `gitops/cluster-config/apps/<profile-name>/`.

### Step 2: Review the operator Applications in the profile

```bash
ls gitops/cluster-config/apps/<profile-name>/
# Each .yaml file is an ArgoCD Application for one operator
```

Check the sync-wave order and paths — some profiles depend on specific overlay versions
or platforms (e.g., equinix profiles need bare-metal specific storage overlays).

### Step 3: Apply the profile

```bash
oc apply -f gitops/apps/<profile-name>/cluster-config.yaml
```

This creates a single ArgoCD Application named `cluster-config`.

### Step 4: Watch ArgoCD sync the sub-applications

```bash
# Watch overall status (run repeatedly)
watch oc get application -n openshift-gitops

# Or watch in ArgoCD console:
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

Applications deploy in sync-wave order. Wave 1 (operators) must reach `Healthy` before
wave 2 (instances) starts.

### Step 5: Verify profile is fully synced

```bash
# All applications should be Synced + Healthy
oc get application -n openshift-gitops | grep -v "Synced.*Healthy"
# If this shows nothing: all apps are healthy
```

## Verification

```bash
# No OutOfSync or Degraded applications
oc get application -n openshift-gitops -o wide

# Key resources for common profiles:
# sno-ocp-virt: check HyperConverged
oc get hyperconverged -n openshift-cnv 2>/dev/null
# acm-gitops-deployment: check MCH
oc get mch -n open-cluster-management 2>/dev/null
# standard-sno-deployment: check StorageCluster
oc get storagecluster -n openshift-storage 2>/dev/null
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| Application `OutOfSync` permanently | Resource exists on cluster but doesn't match Git | Force sync: `oc patch application <name> -n openshift-gitops --type merge -p '{"operation":{"sync":{"force":true}}}'` |
| Wave 2 apps not starting | Wave 1 app not Healthy | Check wave 1 app logs; fix underlying issue |
| `cluster-config` app conflicts | Two profiles applied simultaneously | Each profile creates an app named `cluster-config`; only apply one at a time |
| Prune deletes running resources | App has `prune: true` and resource removed from Git | Set `prune: false` for stateful operator applications |
| App stuck in `Progressing` | Long CRD reconciliation time | Normal for first-time ODF/RHACM installs; wait up to 20 min |
| Missing overlay path | Profile references overlay that doesn't exist | Check actual directory; fix ArgoCD Application `spec.source.path` |

## Related Skills

- [[bootstrap-gitops]] — Must be completed first
- [[troubleshoot-argocd]] — Use if any application stays out of sync
- [[install-odf]] — Run separately if ODF storage needs manual node labeling
