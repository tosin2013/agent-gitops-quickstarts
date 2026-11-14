---
name: troubleshoot-argocd
description: Diagnose and resolve ArgoCD sync failures and application health issues
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc"]
triggers:
  - "ArgoCD not syncing"
  - "sync failed"
  - "application OutOfSync"
  - "argocd error"
  - "argocd stuck"
  - "gitops sync failure"
  - "troubleshoot argocd"
  - "app degraded"
---

# troubleshoot-argocd

## Overview

Diagnoses and resolves ArgoCD sync failures, Degraded applications, and stuck progressions
in the agent-gitops-quickstarts GitOps stack. This skill covers the most common failure
patterns from real-world deployments.

## Quick Diagnostics

Always start here — run all of these before diving into specifics:

```bash
# Overall application status
oc get application -n openshift-gitops -o wide

# Applications that are NOT Synced+Healthy
oc get application -n openshift-gitops -o jsonpath='{range .items[?(@.status.sync.status!="Synced")]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}'

# Recent sync errors (last 20 events)
oc get events -n openshift-gitops --sort-by=.lastTimestamp | tail -20

# ArgoCD server pod health
oc get pods -n openshift-gitops | grep -v Running | grep -v Completed

# ArgoCD server logs (last 50 lines)
oc logs -n openshift-gitops deployment/openshift-gitops-server --tail=50

# ArgoCD application controller logs
oc logs -n openshift-gitops deployment/openshift-gitops-application-controller --tail=50
```

## Failure Pattern Diagnosis

### Pattern 1: Application shows `OutOfSync`

```bash
# Get detailed sync status and messages
oc describe application <app-name> -n openshift-gitops | grep -A 20 "Sync Status"

# See which resources are out of sync
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.sync.comparedTo}'
```

**Common causes and fixes**:

| Cause | Symptom | Fix |
|---|---|---|
| Resource on cluster doesn't match Git | Persistent OutOfSync | Force refresh: `oc annotate application <app> -n openshift-gitops argocd.argoproj.io/refresh=normal` |
| Resource modified outside ArgoCD | OutOfSync with diff | Revert manual change OR update Git to match |
| CRD not installed | `no matches for kind` error | Install the operator that provides the CRD first |
| Namespace missing | `namespaces "X" not found` | Add `CreateNamespace=true` to Application syncOptions |

### Pattern 2: Application shows `Degraded`

```bash
# Check health details
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.health}'

# Check the failing resource
oc get application <app-name> -n openshift-gitops -o jsonpath='{range .status.resources[?(@.health.status!="Healthy")]}{.kind}{" "}{.name}{"\t"}{.health.message}{"\n"}{end}'
```

### Pattern 3: Application stuck in `Progressing`

```bash
# Check which resource is progressing
oc get application <app-name> -n openshift-gitops -o jsonpath='{range .status.resources[?(@.health.status=="Progressing")]}{.kind}{" "}{.name}{"\n"}{end}'

# Check that resource's events
oc get events -n <resource-namespace> --sort-by=.lastTimestamp | tail -10
```

## Steps for Common Fixes

### Fix 1: Trigger a fresh sync

```bash
# Soft refresh (re-compare with Git)
oc annotate application <app-name> -n openshift-gitops \
  argocd.argoproj.io/refresh=normal --overwrite

# Hard refresh (clear cache, re-compare)
oc annotate application <app-name> -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite
```

### Fix 2: Force sync with replace

```bash
oc patch application <app-name> -n openshift-gitops --type merge -p '{
  "operation": {
    "sync": {
      "force": true,
      "syncOptions": ["Replace=true"]
    }
  }
}'
```

### Fix 3: Approve a pending InstallPlan (operator upgrade blocked)

```bash
# Find pending InstallPlans
oc get installplan -A | grep -v Installed

# Approve one
oc patch installplan <name> -n <namespace> --type merge \
  -p '{"spec":{"approved":true}}'
```

### Fix 4: Fix RBAC issues (ArgoCD can't create resources)

```bash
# Verify ArgoCD SA has cluster-admin
oc get clusterrolebinding | grep openshift-gitops
oc describe clusterrolebinding openshift-gitops-openshift-gitops-argocd-application-controller

# If missing, re-apply:
oc apply -f gitops/cluster-config/openshift-gitops/rbac.yaml
```

### Fix 5: Reset a stuck Subscription

```bash
# Delete and recreate the Subscription (ArgoCD will re-create it)
oc delete subscription <name> -n <namespace>
# ArgoCD will recreate it on next sync
```

## Verification

```bash
# After fixing: all applications should be Synced + Healthy
oc get application -n openshift-gitops
# No rows without "Synced" in SYNC column and "Healthy" in HEALTH column
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| `ComparisonError: Failed to load live state` | Resource type CRD not installed | Install the operator providing the CRD; re-sync |
| `failed to sync: one or more objects failed` | RBAC or webhook rejection | Check events in the target namespace |
| `Sync operation already in progress` | Previous sync not completed | Wait 5 min; or delete the operation: `oc patch application <name> -n openshift-gitops --type json -p '[{"op":"remove","path":"/operation"}]'` |
| `unable to recognize STDIN` | Kustomize build failure in source | Run `kustomize build <path>` locally to debug |
| Wave 2 never starts | Wave 1 app not Healthy | Fix Wave 1 health first; check the specific unhealthy resource |
| `Error: unknown field "spec.X"` | Schema validation failure (new OCP version changed CRD) | Update the manifest in Git to use the new field name |

## Related Skills

- [[bootstrap-gitops]] — Re-install ArgoCD if it's completely broken
- [[deploy-profile]] — Start here if deploying a profile for the first time
