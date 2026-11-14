---
name: manage-argocd-apps
description: Create, configure, and manage ArgoCD Applications and app-of-apps profiles for GitOps operator deployment
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "argocd (optional)"]
triggers:
  - "create ArgoCD application"
  - "add operator to profile"
  - "configure ArgoCD sync"
  - "app-of-apps"
  - "sync wave"
  - "ArgoCD application YAML"
  - "gitops profile"
  - "create cluster profile"
  - "argocd app"
---

# manage-argocd-apps

## Overview

Creates and manages ArgoCD Application resources for the agent-gitops-quickstarts
app-of-apps pattern. This skill covers:

- Creating individual operator Applications
- Composing them into a profile (app-of-apps)
- Setting sync waves, prune, and selfHeal correctly
- Applying and monitoring Applications

**App-of-apps pattern used here:**

```
gitops/apps/<profile>/cluster-config.yaml      ← Apply this one (creates the root App)
        │
        ▼ ArgoCD syncs it
gitops/cluster-config/apps/<profile>/          ← ArgoCD reads these Application YAMLs
  operator1.yaml  (wave 1)
  operator2.yaml  (wave 2)
  instance1.yaml  (wave 3)
        │
        ▼ ArgoCD syncs each
gitops/cluster-config/<operator>/operator/overlays/<channel>/  ← Kustomize manifests
```

## Quick Diagnostics

```bash
# List all Applications and their sync/health status
oc get application -n openshift-gitops

# Detailed status for one Application
oc describe application <app-name> -n openshift-gitops

# See which resources are out of sync
oc get application <app-name> -n openshift-gitops \
  -o jsonpath='{range .status.resources[*]}{.kind}{" "}{.name}{" "}{.health.status}{"\n"}{end}'

# See sync history
oc get application <app-name> -n openshift-gitops \
  -o jsonpath='{range .status.history[*]}{.id}{" "}{.deployedAt}{" "}{.revision}{"\n"}{end}'

# Check the app-of-apps root application
oc get application cluster-config -n openshift-gitops
```

## Step 1: Understand the two-level structure

**Level 1 — Root Application** (`gitops/apps/<profile>/cluster-config.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-config          # always named cluster-config (one per cluster)
  namespace: openshift-gitops
spec:
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  project: default
  source:
    path: gitops/cluster-config/apps/<profile>   # ← points to the app set directory
    repoURL: https://github.com/tosin2013/agent-gitops-quickstarts.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Level 2 — Per-operator Applications** (`gitops/cluster-config/apps/<profile>/<operator>.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <operator-name>
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  destination:
    namespace: <operator-namespace>
    server: https://kubernetes.default.svc
  project: default
  source:
    path: gitops/cluster-config/<operator-name>/operator/overlays/<channel>
    repoURL: https://github.com/tosin2013/agent-gitops-quickstarts.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

## Step 2: Choose the right sync wave

Sync waves control deployment order. ArgoCD waits for all resources in wave N to be
`Healthy` before starting wave N+1.

| Wave | Use for | Examples |
|---|---|---|
| 1 | Infrastructure operators | local-storage, openshift-virtualization, openshift-pipelines |
| 2 | Application operators (depend on wave 1) | ODF operator, ACM, AAP operator, DevSpaces |
| 3 | Operand instances (operator must be Ready) | StorageSystem, HyperConverged CR, AAP instance |
| 4 | Deep instances (depend on wave 3) | ODF instance on bare-metal (needs LSO ready first) |
| 5 | Deepest dependency | Virt instance on equinix (needs NMState + storage) |

**Rule of thumb:** add 1 wave for each hop in the dependency chain.

## Step 3: Choose prune and selfHeal settings

| Setting | Value | When |
|---|---|---|
| `prune: true` | Deletes resources removed from Git | Stateless operators (Pipelines, GitOps itself) |
| `prune: false` | Preserves resources even if removed from Git | **Storage, databases, stateful operators** — use this by default |
| `selfHeal: true` | Re-syncs if someone manually changes a resource | Almost always true |
| `selfHeal: false` | Allows manual changes to persist | Rarely used; useful during active debugging |

> **Default for new operators:** `prune: false, selfHeal: true`
> Change to `prune: true` only when you're confident the operator is fully stateless.

## Step 4: Create a new profile (app-of-apps)

If adding a new cluster profile:

```bash
PROFILE="my-new-profile"
mkdir -p "gitops/apps/$PROFILE"
mkdir -p "gitops/cluster-config/apps/$PROFILE"
```

**Root Application** (`gitops/apps/$PROFILE/cluster-config.yaml`):
```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-config
  namespace: openshift-gitops
spec:
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  project: default
  source:
    path: gitops/cluster-config/apps/my-new-profile
    repoURL: https://github.com/tosin2013/agent-gitops-quickstarts.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Then add per-operator Application YAMLs to `gitops/cluster-config/apps/my-new-profile/`.

## Step 5: Apply and watch

```bash
# Apply the root Application (this starts the app-of-apps chain):
oc apply -f gitops/apps/my-new-profile/cluster-config.yaml

# Watch all applications:
watch oc get application -n openshift-gitops

# Check a specific application's sync details:
oc describe application <name> -n openshift-gitops | grep -A 20 "Sync Status"
```

## Step 6: Trigger manual operations

```bash
# Force a refresh (re-compare with Git without syncing):
oc annotate application <name> -n openshift-gitops \
  argocd.argoproj.io/refresh=normal --overwrite

# Force a hard refresh (clear cache):
oc annotate application <name> -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite

# Force sync with replace (use cautiously):
oc patch application <name> -n openshift-gitops --type merge -p \
  '{"operation":{"sync":{"force":true}}}'

# Delete a stuck sync operation:
oc patch application <name> -n openshift-gitops --type json \
  -p '[{"op":"remove","path":"/operation"}]'
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| Wave 2 apps never start | Wave 1 app not reaching Healthy | Fix wave 1 app health first; check `oc describe application <wave1-app>` |
| `cluster-config` app conflict | Two profiles applied at same time (both create an App named `cluster-config`) | Delete one: `oc delete application cluster-config -n openshift-gitops`; apply only one profile |
| App shows `OutOfSync` permanently | Resource on cluster differs from Git; prune=false blocking cleanup | Check diff: `oc describe application <name> | grep -A5 "Diff"`; either fix Git or delete the diverged resource |
| App stuck in `Progressing` | A Deployment/StatefulSet isn't reaching desired replicas | Check pod events in target namespace: `oc get events -n <ns> --sort-by=.lastTimestamp` |
| App created but won't sync — "permission denied" | ArgoCD SA missing RBAC for the resource type | Check `oc describe application <name>` for RBAC errors; the ArgoCD SA has cluster-admin via `gitops/cluster-config/openshift-gitops/rbac.yaml` |
| Operator Application syncs but instance Application won't start | Instance CR needs CRD from operator — operator not fully ready | Increase the sync-wave gap; check operator CSV: `oc get csv -n <ns> | grep <operator>` |
| App health stays `Unknown` | CRD for health check not known to ArgoCD | Add a resource exclusion or wait — ArgoCD learns new CRDs after restart |

## Related Skills

- [[create-kustomize-operator]] — creating the Kustomize base + overlays that Applications reference
- [[troubleshoot-argocd]] — deeper ArgoCD sync failure diagnosis
- [[deploy-profile]] — deploying a full pre-built profile
- [[bootstrap-gitops]] — installing ArgoCD itself first
