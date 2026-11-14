---
name: install-aap
description: Install Ansible Automation Platform (AAP) operator, controller instance, and hub
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "kustomize"]
triggers:
  - "Ansible Automation Platform"
  - "AAP"
  - "install AAP"
  - "ansible controller"
  - "automation hub"
  - "install ansible"
---

# install-aap

## Overview

Installs Ansible Automation Platform (AAP) on OpenShift. AAP provides enterprise automation
with Ansible Controller (formerly AWX/Tower), Automation Hub (private content repository),
and Event-Driven Ansible.

The operator deploys in 3 waves:
1. AAP operator (Subscription + OperatorGroup)
2. AnsibleAutomationPlatform instance (Controller)
3. AutomationHub instance

## Prerequisites

- ArgoCD bootstrapped: [[bootstrap-gitops]] completed
- Sufficient resources: AAP requires ~16 cores, 32Gi RAM minimum
- Storage: persistent volumes required for database and hub artifacts

## Quick Diagnostics

```bash
# Check AAP operator status
oc get subscription -n aap 2>/dev/null || echo "AAP not installed"
oc get csv -n aap | grep ansible

# Check AAP instance
oc get ansibleautomationplatform -A

# Check AutomationHub
oc get automationhub -A

# Check AAP pods
oc get pods -n aap | grep -v Running | grep -v Completed

# Get AAP console URL
oc get route -n aap | grep -E "controller|automation"
```

## Steps

### Step 1: Select the right operator overlay

| Cluster Scope | Path |
|---|---|
| Cluster-scoped (recommended) | `gitops/cluster-config/ansible-automation-platform/operator/overlays/stable-2.5-cluster-scoped` |
| Namespace-scoped | `gitops/cluster-config/ansible-automation-platform/operator/overlays/stable-2.5` |

### Step 2: Apply the AAP operator (wave 1)

```bash
oc apply -k gitops/cluster-config/ansible-automation-platform/operator/overlays/stable-2.5-cluster-scoped
```

Wait for operator to be ready:
```bash
until oc get csv -n aap | grep -q "ansible-automation-platform.*Succeeded"; do
  echo "Waiting for AAP CSV..."; sleep 15
done
```

### Step 3: Apply the AAP controller instance (wave 2)

```bash
# Default instance:
oc apply -k gitops/cluster-config/ansible-automation-platform/instance/overlays/default

# Cloud-specific:
# AWS: oc apply -k gitops/cluster-config/ansible-automation-platform/instance/overlays/aws
# Azure: oc apply -k gitops/cluster-config/ansible-automation-platform/instance/overlays/azure
```

### Step 4: Apply the AutomationHub instance (wave 3)

```bash
oc apply -k gitops/cluster-config/ansible-automation-platform/hub-instance/overlays/default
```

### Step 5: Wait for all components to be ready

```bash
# Wait for controller
oc wait ansibleautomationplatform -n aap --all \
  --for=condition=Successful --timeout=600s

# Get admin password
oc get secret -n aap aap-admin-password -o jsonpath='{.data.password}' | base64 -d
```

## Verification

```bash
# Controller and Hub should be Running
oc get ansibleautomationplatform -A
oc get automationhub -A

# All pods running
oc get pods -n aap | grep -v Running | grep -v Completed

# Get console URLs
oc get route -n aap
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| Controller pod `Pending` | No PVC for database (no storage class) | Install ODF or configure default StorageClass |
| `Subscription` stuck | Wrong channel or catalog | Current channel: `stable-2.5-cluster-scoped`; check: `oc get packagemanifest ansible-automation-platform -n openshift-marketplace` |
| Hub `ProvisionFailed` | Insufficient resources | Hub needs ~8Gi RAM; check node capacity |
| Admin password secret not created | Instance not fully reconciled | Wait for `ansibleautomationplatform` condition `Successful` |
| Route not accessible | OAuth/ingress not configured | Check `oc get oauth cluster` for external IdP conflicts |
| profiles reference `stable-2.4` | Old overlay path | Overlay was updated to `stable-2.5`; check ArgoCD Application path |

## Related Skills

- [[bootstrap-gitops]] — Must be completed first
- [[install-odf]] — Recommended for database persistent storage
- [[deploy-profile]] — Use `aap-instance`, `baremetal-rhacm-hub`, or `developer-env` profiles
