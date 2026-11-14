---
name: install-odf
description: Install OpenShift Data Foundation (ODF/Ceph) operator and StorageCluster on OCP
version: "1.1"
compatibility:
  ocp: ">=4.9"
  platforms: ["bare-metal", "kvm", "aws", "gcp", "azure", "vsphere", "equinix"]
  tools: ["oc", "kustomize"]
triggers:
  - "install ODF"
  - "install openshift data foundation"
  - "set up storage"
  - "install ceph"
  - "configure persistent storage"
  - "install rook ceph"
---

# install-odf

## Overview

Installs OpenShift Data Foundation (ODF) — the Ceph-based storage solution for multi-node
OpenShift clusters. ODF provides block (RBD), file (CephFS), and object (Noobaa/S3) storage.
For single-node clusters, use `install-odf-lvm` (ODF-LVM) instead.

**OCP 5.0 note**: ODF on OCP 5.0 requires RHCOS 10 and x86-64-v3+ CPU microarchitecture.

## Prerequisites

- ArgoCD bootstrapped: [[bootstrap-gitops]] completed
- At least 3 worker nodes with dedicated storage disks (for Ceph)
- Nodes labeled for ODF storage: `cluster.ocs.openshift.io/openshift-storage=""`
- For OCP 5.0: nodes must meet x86-64-v3+ CPU requirement

## Quick Diagnostics

```bash
# Check ODF operator status
oc get subscription odf-operator -n openshift-storage 2>/dev/null || echo "ODF not yet installed"
oc get csv -n openshift-storage | grep odf

# Check storage nodes
oc get nodes -l cluster.ocs.openshift.io/openshift-storage

# Check StorageCluster
oc get storagecluster -n openshift-storage

# Check ODF pods
oc get pods -n openshift-storage | grep -v Running | grep -v Completed

# Check storage classes created by ODF
oc get storageclass | grep -E "ceph|ocs|odf|noobaa"
```

## Steps

### Step 1: Select the right overlays for your OCP version and platform

**Operator channel** (match your OCP version):

| OCP Version | Operator Overlay |
|---|---|
| 4.9 | `operator/overlays/stable-4.9` |
| 4.10–4.22 | `operator/overlays/stable-4.X` (replace X with your version) |
| 5.0 | `operator/overlays/stable-5.0` |

**Current recommended**: `stable-4.22` (OCP 4.22, latest 4.x as of Nov 2026)

**StorageCluster instance** (match your platform):

| Platform | Instance Overlay | Storage Class |
|---|---|---|
| AWS | `instance/overlays/aws` | `gp2` |
| GCP | `instance/overlays/gcp` | `standard-csi` |
| Azure | `instance/overlays/azure` | `managed-premium` |
| VMware vSphere | `instance/overlays/vsphere` | vSphere datastore |
| Bare-metal / Equinix | `instance/overlays/bare-metal` | local-storage |
| KVM / libvirt | `instance/overlays/kvm` | local-storage |
| SNO | Use ODF-LVM (`odf-lvm-operator`) instead — ODF Ceph needs 3 nodes |

### Step 2: Apply the ODF operator via ArgoCD (or directly)

**Via ArgoCD Application** (recommended — add to your profile):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-data-foundation-operator
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  destination:
    namespace: openshift-storage
    server: https://kubernetes.default.svc
  project: default
  source:
    path: gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/stable-4.19
    repoURL: https://github.com/tosin2013/sno-quickstarts.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**Directly with kustomize**:
```bash
oc apply -k gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/stable-4.19
```

### Step 3: Wait for operator to be ready

```bash
oc rollout status deployment/ocs-operator -n openshift-storage --timeout=300s
oc get csv -n openshift-storage | grep -i odf
```

### Step 4: Label storage nodes

```bash
# Label the nodes that will host ODF storage (minimum 3)
oc label node <node1> cluster.ocs.openshift.io/openshift-storage=""
oc label node <node2> cluster.ocs.openshift.io/openshift-storage=""
oc label node <node3> cluster.ocs.openshift.io/openshift-storage=""
```

### Step 5: Apply a StorageCluster instance

Choose the platform-appropriate overlay:
```bash
# For bare metal:
oc apply -k gitops/cluster-config/openshift-data-foundation-operator/instance/overlays/bare-metal

# For AWS:
oc apply -k gitops/cluster-config/openshift-data-foundation-operator/instance/overlays/aws

# For VMware vSphere:
oc apply -k gitops/cluster-config/openshift-data-foundation-operator/instance/overlays/vsphere
```

### Step 6: Enable the ODF console plugin

```bash
# The base includes a job that enables the console plugin
# Verify it ran:
oc get jobs -n openshift-storage | grep console
```

## Verification

```bash
# StorageCluster should be in Ready phase
oc get storagecluster -n openshift-storage -o jsonpath='{.items[0].status.phase}'
# Expected: Ready

# Check all ODF pods are Running
oc get pods -n openshift-storage | grep -v Running | grep -v Completed

# Verify storage classes
oc get storageclass
# Expected: ocs-storagecluster-ceph-rbd, ocs-storagecluster-cephfs, openshift-storage.noobaa.io
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| StorageCluster stuck in `Progressing` | Insufficient storage nodes or no raw disks | Ensure 3 nodes labeled, each with an unformatted disk |
| `Error: LocalVolume not found` | Using bare-metal overlay without local-storage operator | Install `install-local-storage` skill first |
| OSD pods `CrashLoopBackOff` | Disks already contain data/partitions | Wipe disks: `sgdisk --zap-all /dev/<disk>` on each node |
| CSV shows `Failed` | ODF version incompatible with OCP version | Match overlay version to `oc version` output |
| Noobaa pod pending | Insufficient memory on nodes | Noobaa requires ~8Gi; check node resources |
| OCP 5.0: pod fails with `Illegal instruction` | Node CPU doesn't meet x86-64-v3+ requirement | Check CPU: `grep -m1 avx512 /proc/cpuinfo` |

## Related Skills

- [[bootstrap-gitops]] — Must be completed first
- [[install-virtualization]] — Can run in parallel with ODF after operator is Ready
- [[troubleshoot-argocd]] — Use if ArgoCD fails to sync ODF resources
