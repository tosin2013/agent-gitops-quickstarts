---
name: install-virtualization
description: Install OpenShift Virtualization (CNV/KubeVirt) operator and HyperConverged instance
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "kustomize"]
triggers:
  - "OpenShift Virtualization"
  - "CNV"
  - "KubeVirt"
  - "install virtualization"
  - "run virtual machines"
  - "install kubevirt"
  - "install cnv"
---

# install-virtualization

## Overview

Installs OpenShift Virtualization (formerly Container Native Virtualization / CNV), which
enables running traditional virtual machines alongside containers on OpenShift. Based on KubeVirt.

Two deployment topologies are supported:
- **SNO** (`overlays/sno`): Uses hostpath-provisioner for VM storage; suitable for single-node
- **Standard** (`overlays/standard`): Uses shared storage (ODF/NFS); for multi-node clusters

## Prerequisites

- ArgoCD bootstrapped: [[bootstrap-gitops]] completed
- For SNO overlay: [[install-odf]] not required; hostpath-provisioner is used instead
- For standard overlay: shared storage (ODF recommended)
- CPU virtualization extensions enabled (Intel VT-x / AMD-V) on nodes

## Quick Diagnostics

```bash
# Check if CNV is installed
oc get subscription kubevirt-hyperconverged -n openshift-cnv 2>/dev/null || echo "Not installed"
oc get csv -n openshift-cnv | grep kubevirt

# Check HyperConverged instance
oc get hyperconverged -n openshift-cnv

# Check CNV pods
oc get pods -n openshift-cnv | grep -v Running | grep -v Completed

# Check if virtualization is working (try creating a test VM)
oc get vmi -A 2>/dev/null

# Check node CPU virtualization support
oc get node -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.cpu}{"\n"}{end}'
```

## Steps

### Step 1: Choose the right overlay

| Topology | Path |
|---|---|
| SNO (single-node, hostpath storage) | `gitops/cluster-config/openshift-virtualization/operator/overlays/sno` |
| Standard (multi-node, shared storage) | `gitops/cluster-config/openshift-virtualization/operator/overlays/standard` |
| OCP 5.0 | `gitops/cluster-config/openshift-virtualization/operator/overlays/stable-5.0` |

### Step 2: Apply the CNV operator

```bash
# SNO:
oc apply -k gitops/cluster-config/openshift-virtualization/operator/overlays/sno

# Standard:
oc apply -k gitops/cluster-config/openshift-virtualization/operator/overlays/standard
```

### Step 3: Wait for operator CSV to be ready

```bash
# Wait for CSV to reach Succeeded
until oc get csv -n openshift-cnv | grep -q "kubevirt.*Succeeded"; do
  echo "Waiting for CNV CSV..."; sleep 15
done
echo "CNV operator ready"
```

### Step 4: Apply the HyperConverged instance

```bash
oc apply -f gitops/cluster-config/openshift-virtualization/instance/hyperconverged.yaml
```

### Step 5: Wait for HyperConverged to be ready

```bash
oc wait hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  --for=condition=Available --timeout=600s
```

## Verification

```bash
# HyperConverged should be Available
oc get hyperconverged -n openshift-cnv

# Check CNV components
oc get pods -n openshift-cnv | grep -v Running | grep -v Completed

# Verify VM API is available
oc api-resources | grep kubevirt.io

# Check storage class for VM disks
oc get storageclass | grep -E "hostpath|ceph"
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| HyperConverged stuck in `Progressing` | virt-handler pods not scheduling | Check node taints: `oc describe node | grep Taint` |
| `virt-launcher` pods `Pending` | No storage class for VM disks | For SNO: install hostpath-provisioner; for HA: install ODF |
| CPU virtualization check fails | Hardware virtualization disabled | Enable VT-x/AMD-V in BIOS/hypervisor settings |
| `HyperConverged` condition `False` with `SSP not available` | SSP operator dependency not met | Wait longer; `oc get ssp -n openshift-cnv` |
| Live migration fails on SNO | SNO has only 1 node; live migration requires 2+ | Expected; live migration not supported on SNO |
| OCP 5.0 migration fails with API error | Using old `HyperConverged` v1beta1 without upgrade path | Check CSV for supported API versions |

## Related Skills

- [[bootstrap-gitops]] — Must be completed first
- [[install-odf]] — Required for standard (multi-node) deployments
- [[deploy-profile]] — Use `sno-ocp-virt` profile to deploy both together
