---
name: create-kustomize-operator
description: Scaffold a new operator into the repo using the base/overlay Kustomize pattern and add an ArgoCD Application YAML to a profile
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "kustomize or oc kustomize"]
triggers:
  - "add a new operator"
  - "create kustomize overlay"
  - "scaffold operator config"
  - "add operator to gitops"
  - "create operator subscription"
  - "new operator overlay"
  - "add to gitops catalog"
---

# create-kustomize-operator

## Overview

Scaffolds a new operator into the `gitops/cluster-config/` directory following the
established base/overlay Kustomize pattern. Also creates an ArgoCD Application YAML
so the operator can be added to a cluster profile.

**Check the gitops-catalog first** — before writing from scratch, check whether the
operator already has a Kustomize config in:
- `tosin2013/gitops-catalog` (Tosin's fork): https://github.com/tosin2013/gitops-catalog
- `redhat-cop/gitops-catalog` (upstream community): https://github.com/redhat-cop/gitops-catalog

If it's there, copy that base and adapt it. This saves significant effort.

## Pattern Reference

The repo uses a two-tier split for every operator:

```
gitops/cluster-config/<operator-name>/
  operator/
    base/                          # Shared manifests — never applied directly
      kustomization.yaml           # lists all resources
      <op>-namespace.yaml          # Namespace CR
      <op>-operatorgroup.yaml      # OperatorGroup CR
      <op>-subscription.yaml       # Subscription (channel: patch-me-see-overlays-dir)
    overlays/
      <channel-name>/              # e.g. stable-4.22, latest
        kustomization.yaml         # resources: [../../base], patches: [patch-channel.yaml]
        patch-channel.yaml         # JSON Patch: replace /spec/channel with actual value
        README.md
  instance/                        # Optional: operand CR (StorageCluster, HyperConverged, etc.)
    base/
    overlays/<platform>/
```

## Quick Diagnostics

```bash
# Find the operator package name and available channels
oc get packagemanifest -n openshift-marketplace | grep -i <keyword>

# Get full channel list for an operator
oc describe packagemanifest <package-name> -n openshift-marketplace \
  | grep -A 5 "Channel Name"

# Get current default channel
oc get packagemanifest <package-name> -n openshift-marketplace \
  -o jsonpath='{.status.defaultChannel}'

# Get the install namespace and mode
oc get packagemanifest <package-name> -n openshift-marketplace \
  -o jsonpath='{.status.channels[0].currentCSVDesc.installModes}'
```

## Steps

### Step 1: Check the gitops-catalog first

```bash
# Clone Tosin's gitops-catalog fork and search for the operator:
git clone --depth=1 https://github.com/tosin2013/gitops-catalog.git /tmp/gitops-catalog
ls /tmp/gitops-catalog/ | grep -i <operator-name>

# If found, copy it as your starting point:
cp -r /tmp/gitops-catalog/<operator-name> gitops/cluster-config/
```

If the operator is in the catalog, skip to Step 5 (overlay) and Step 6 (ArgoCD App).

### Step 2: Discover operator metadata

```bash
OPERATOR_NAME="<operator-package-name>"  # e.g. openshift-pipelines-operator-rh

oc get packagemanifest "$OPERATOR_NAME" -n openshift-marketplace \
  -o jsonpath='{.status.defaultChannel}'

oc get packagemanifest "$OPERATOR_NAME" -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}'

# Get install namespace from CSV annotations:
oc get packagemanifest "$OPERATOR_NAME" -n openshift-marketplace \
  -o jsonpath='{.status.channels[0].currentCSVDesc.annotations.operatorframework\.io/suggested-namespace}'
```

### Step 3: Create the directory structure

```bash
OPERATOR_DIR="gitops/cluster-config/<operator-name>"
mkdir -p "$OPERATOR_DIR/operator/base"
mkdir -p "$OPERATOR_DIR/operator/overlays/<default-channel>"
```

### Step 4: Create the base files

**`operator/base/kustomization.yaml`** — list all resources, set namespace:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: <operator-namespace>

resources:
  - <operator>-namespace.yaml
  - <operator>-operatorgroup.yaml
  - <operator>-subscription.yaml
```

**`operator/base/<operator>-namespace.yaml`**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <operator-namespace>
```

**`operator/base/<operator>-operatorgroup.yaml`** (for AllNamespaces mode, omit `targetNamespaces`):
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: <operator-name>-og
  namespace: <operator-namespace>
spec: {}
```

**`operator/base/<operator>-subscription.yaml`** — use placeholder channel:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: <operator-package-name>
  namespace: <operator-namespace>
spec:
  channel: patch-me-see-overlays-dir
  installPlanApproval: Automatic
  name: <operator-package-name>
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

> **Important**: always set `channel: patch-me-see-overlays-dir` in the base.
> Never hardcode a real channel here — that belongs in the overlay's patch file.

### Step 5: Create the first overlay

**`operator/overlays/<channel>/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: <operator-namespace>

resources:
  - ../../base

patches:
  - target:
      group: operators.coreos.com
      version: v1alpha1
      kind: Subscription
      name: <operator-package-name>
      namespace: <operator-namespace>
    path: patch-channel.yaml
```

**`operator/overlays/<channel>/patch-channel.yaml`** — JSON Patch RFC 6902:
```yaml
- op: replace
  path: /spec/channel
  value: <actual-channel-name>
```

**`operator/overlays/<channel>/README.md`**:
```markdown
# <Operator Name> — <channel> Overlay

Installs <Operator Name> on OCP <version>.
Channel: `<channel>`
```

### Step 6: Verify the overlay builds

```bash
# This must succeed with no errors (warnings about deprecated fields are OK):
oc kustomize gitops/cluster-config/<operator-name>/operator/overlays/<channel>/
```

### Step 7: Create an ArgoCD Application YAML

Add `gitops/cluster-config/apps/<profile>/<operator-name>.yaml`:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <operator-name>
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # 1-2 for operators, 3-5 for instances
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
      prune: false      # use true for stateless operators, false for storage/stateful
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**Sync wave guidelines:**
| Wave | Use for |
|---|---|
| 1 | Infrastructure operators (storage, networking, CNV) |
| 2 | Application operators that depend on wave 1 |
| 3 | Operand instances (StorageCluster, HyperConverged, etc.) |
| 4–5 | Deep dependencies (instances that need wave 3 to be Ready first) |

**Prune guidelines:**
| `prune: true` | `prune: false` |
|---|---|
| Stateless operators (Pipelines, Gitops) | Storage operators (ODF, LSO) |
| Reversible resources | Irreversible/stateful resources |

### Step 8: Update llm.txt

Add an entry for the new operator under the appropriate category in `llm.txt`:

```
- **<operator-display-name>** — <description>
  Channels: <channel-list>
  Namespace: <namespace> | Package: <package-name>
```

### Step 9: Commit

```bash
git add gitops/cluster-config/<operator-name>/
git add gitops/cluster-config/apps/<profile>/<operator-name>.yaml
git add llm.txt
git commit -m "feat(operator): add <operator-name> kustomize config and ArgoCD Application"
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| `oc kustomize` fails with "no matches for kind" | CRD not yet installed; overlay references a CR before operator is ready | This is a build-time check — it's fine to have CRs for the operand in a separate `instance/` overlay applied later via sync-wave |
| `channel: patch-me-see-overlays-dir` applied to cluster | Base was applied directly instead of through an overlay | Always `oc apply -k overlays/<channel>/`, never `oc apply -k base/` |
| OperatorGroup conflict | Another OperatorGroup already exists in the namespace | Most operators use `openshift-operators` (global); if so, omit the OperatorGroup |
| Subscription stuck `UpgradePending` | Manual installPlan approval or channel mismatch | Check `oc get installplan -n <ns>` and verify channel name against `oc get packagemanifest` |
| ArgoCD shows `OutOfSync` immediately after apply | Resource exists on cluster from a previous install | Use `oc apply` (not `oc create`) or delete the conflicting resource first |
| Operator not found in `redhat-operators` catalog | Wrong `source` or operator is in `certified-operators` | Check: `oc get packagemanifest <name> -n openshift-marketplace -o jsonpath='{.status.catalogSource}'` |

## Related Skills

- [[manage-argocd-apps]] — managing the ArgoCD Application side of this workflow
- [[troubleshoot-argocd]] — if the new operator's Application won't sync
- [[deploy-profile]] — adding the new operator to a full cluster profile
