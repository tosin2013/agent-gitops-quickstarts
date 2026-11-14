---
name: install-acm
description: Install Red Hat Advanced Cluster Management (RHACM) hub operator and MultiClusterHub
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "kustomize"]
triggers:
  - "install RHACM"
  - "hub cluster"
  - "ACM"
  - "advanced cluster management"
  - "install ACM"
  - "set up hub"
  - "multicluster management"
---

# install-acm

## Overview

Installs Red Hat Advanced Cluster Management (RHACM) on a hub cluster. RHACM provides
centralized management of a fleet of OpenShift clusters including lifecycle management,
policy governance, observability, and GitOps (via ApplicationSets/ArgoCD integration).

After installing RHACM, use [[configure-ztp]] to provision spoke clusters via ZTP.

## Prerequisites

- ArgoCD bootstrapped: [[bootstrap-gitops]] completed
- Hub cluster with sufficient resources (8 cores, 32Gi RAM minimum; more for large fleets)
- For HA hub: 3-node cluster or dedicated infrastructure nodes
- OCP 5.0: use `stable-5.0` channel overlay

## Quick Diagnostics

```bash
# Check RHACM operator
oc get subscription advanced-cluster-management -n open-cluster-management 2>/dev/null || echo "Not installed"
oc get csv -n open-cluster-management | grep -i acm

# Check MultiClusterHub
oc get multiclusterhub -n open-cluster-management

# Check hub status
oc get mch -n open-cluster-management -o jsonpath='{.items[0].status.phase}'

# Check hub components
oc get pods -n open-cluster-management | grep -v Running | grep -v Completed

# Check managed clusters
oc get managedcluster

# Check RHACM version
oc get csv -n open-cluster-management | grep advanced-cluster
```

## Steps

### Step 1: Select the right operator overlay

| OCP / ACM Version | Overlay |
|---|---|
| ACM 2.11 (OCP 4.14-4.19) | `gitops/cluster-config/rhacm-operator/overlays/release-2.11` |
| ACM 5.0 (OCP 5.0) | `gitops/cluster-config/rhacm-operator/overlays/stable-5.0` |

### Step 2: Apply the RHACM operator

**Via ArgoCD** (recommended):
```bash
oc apply -f gitops/cluster-config/apps/acm-gitops-deployment/advanced-cluster-management.yaml
```

**Directly**:
```bash
# OCP 4.x (ACM 2.11):
oc apply -k gitops/cluster-config/rhacm-operator/overlays/release-2.11

# OCP 5.0 (ACM 5.0):
oc apply -k gitops/cluster-config/rhacm-operator/overlays/stable-5.0
```

### Step 3: Wait for RHACM operator to be ready

```bash
until oc get csv -n open-cluster-management | grep -q "advanced-cluster-management.*Succeeded"; do
  echo "Waiting for RHACM CSV..."; sleep 15
done
```

### Step 4: Apply the MultiClusterHub instance

Choose the right instance overlay for your hub topology:

```bash
# Basic (single-node hub, dev/test):
oc apply -k gitops/cluster-config/rhacm-instance/overlays/basic

# HA (3-node hub):
oc apply -k gitops/cluster-config/rhacm-instance/overlays/ha

# HA with infrastructure nodes:
oc apply -k gitops/cluster-config/rhacm-instance/overlays/ha-infra
```

### Step 5: Wait for MultiClusterHub to be running

```bash
oc wait multiclusterhub multiclusterhub -n open-cluster-management \
  --for=jsonpath='{.status.phase}'=Running --timeout=900s
```

## Verification

```bash
# MultiClusterHub phase should be Running
oc get mch -n open-cluster-management

# Hub is registered as a managed cluster (local-cluster)
oc get managedcluster local-cluster

# All hub pods running
oc get pods -n open-cluster-management | grep -v Running | grep -v Completed

# RHACM console accessible
oc get route multicloud-console -n open-cluster-management -o jsonpath='{.spec.host}'
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| MCH stuck in `Installing` for >15min | Insufficient resources or image pull failure | `oc get events -n open-cluster-management --sort-by=.lastTimestamp` |
| `multicluster-engine` CRD not found | MCE operator not installed | MCE is a dependency; RHACM 2.x auto-installs it; check `oc get csv -n multicluster-engine` |
| `local-cluster` shows `Unknown` | Hub cluster DNS issue | Check `oc get pods -n open-cluster-management-hub` |
| ACM 5.0 with `stable-5.0` channel not found | Catalog not updated | `oc get packagemanifest advanced-cluster-management -n openshift-marketplace` |
| Hub memory OOM | Insufficient memory on hub nodes | Minimum 32Gi; for >500 spokes use dedicated infra nodes |

## Related Skills

- [[bootstrap-gitops]] — Must be completed first
- [[configure-ztp]] — Use after RHACM to provision spoke clusters
- [[deploy-profile]] — Use `acm-gitops-deployment` or `baremetal-rhacm-hub` profile
