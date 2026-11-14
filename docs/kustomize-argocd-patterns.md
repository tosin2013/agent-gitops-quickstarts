# Kustomize + ArgoCD Patterns Reference

This document explains the structural patterns used throughout `agent-gitops-quickstarts`.
Read this before adding a new operator or profile.

---

## The Two-Level App-of-Apps Pattern

```
gitops/apps/<profile>/cluster-config.yaml      ← User applies this once
        │  (ArgoCD Application pointing at app set directory)
        ▼
gitops/cluster-config/apps/<profile>/          ← ArgoCD reads these (per-operator Applications)
  <operator1>.yaml   sync-wave: "1"
  <operator2>.yaml   sync-wave: "2"
  <instance1>.yaml   sync-wave: "3"
        │
        ▼ ArgoCD applies each via Kustomize
gitops/cluster-config/<operator>/operator/overlays/<channel>/
  kustomization.yaml   →   references   →   operator/base/
  patch-channel.yaml   →   patches      →   base subscription channel
```

**Rule:** Users only ever apply the root Application (`cluster-config.yaml`). Everything else is managed by ArgoCD.

---

## Kustomize Base/Overlay Structure

Every operator in `gitops/cluster-config/` follows this layout:

```
<operator-name>/
  operator/
    base/                              # Never applied directly
      kustomization.yaml
      <op>-namespace.yaml
      <op>-operatorgroup.yaml
      <op>-subscription.yaml          # channel: patch-me-see-overlays-dir
    overlays/
      <channel>/                      # e.g. stable-4.22, latest, release-2.11
        kustomization.yaml
        patch-channel.yaml
        README.md
  instance/                           # Operand CR (optional)
    base/
    overlays/
      <platform>/                     # e.g. aws, bare-metal, gcp, sno
```

### What lives in `base/`

| File | Purpose |
|---|---|
| `kustomization.yaml` | Lists all resources; sets the namespace |
| `*-namespace.yaml` | The `Namespace` CR for the operator |
| `*-operatorgroup.yaml` | The `OperatorGroup` CR (AllNamespaces or SingleNamespace) |
| `*-subscription.yaml` | The `Subscription` CR with **placeholder channel** |

The Subscription's `spec.channel` is always `patch-me-see-overlays-dir` in base — it is never a real channel name. Real channel values live only in overlay patch files.

### What lives in `overlays/<channel>/`

**`kustomization.yaml`** — references base and applies the channel patch:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: openshift-storage
resources:
  - ../../base
patches:
  - target:
      group: operators.coreos.com
      version: v1alpha1
      kind: Subscription
      name: odf-operator
      namespace: openshift-storage
    path: patch-channel.yaml
```

**`patch-channel.yaml`** — RFC 6902 JSON Patch replacing only the channel value:
```yaml
- op: replace
  path: /spec/channel
  value: stable-4.22
```

### What lives in `instance/overlays/<platform>/`

Platform-specific operand configuration. For ODF:

| Platform | File | Key difference |
|---|---|---|
| `aws` | `storagecluster.yaml` | storageClassName: `gp2` |
| `gcp` | `storagecluster.yaml` | storageClassName: `standard-csi` |
| `azure` | `storagecluster.yaml` | storageClassName: `managed-premium` |
| `bare-metal` | `storagecluster.yaml` | local-devices annotation, flexibleScaling |
| `kvm` | `storagecluster.yaml` | local-block storage class |
| `sno` | `storagecluster.yaml` | single-node minimal config |

---

## ArgoCD Application YAML Structure

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-data-foundation-operator   # unique within openshift-gitops namespace
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "2"        # deployment order (see sync waves below)
spec:
  destination:
    namespace: openshift-storage             # target namespace for resources
    server: https://kubernetes.default.svc   # always this value for in-cluster
  project: default
  source:
    path: gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/stable-4.22
    repoURL: https://github.com/tosin2013/agent-gitops-quickstarts.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: false       # never prune storage operators
      selfHeal: true     # re-sync if manually changed
    syncOptions:
    - CreateNamespace=true
```

### Critical fields

| Field | Notes |
|---|---|
| `spec.source.path` | Always points at an **overlay** directory, never `base/` |
| `spec.destination.namespace` | The operator's target namespace (must match overlay's namespace setting) |
| `syncPolicy.automated` | Enables continuous GitOps — without this, syncs are manual |
| `syncOptions: CreateNamespace=true` | Let ArgoCD create namespaces; Namespace is also in base as explicit resource |

---

## Sync Waves

ArgoCD waits for all resources in wave N to reach `Healthy` before starting wave N+1.
Annotate with `argocd.argoproj.io/sync-wave: "N"`.

| Wave | Purpose | Examples in this repo |
|---|---|---|
| **1** | Infrastructure operators | local-storage, openshift-virtualization, openshift-pipelines, NMState |
| **2** | Application operators (need wave 1) | ODF operator, ACM, AAP operator, DevSpaces |
| **3** | Operand instances | StorageSystem, HyperConverged CR, AAP instance, ACM MultiClusterHub |
| **4** | Deep instances (depend on wave 3) | ODF bare-metal instance (needs LSO instance ready) |
| **5** | Deepest dependencies | Virtualization instance on Equinix (needs NMState + storage) |

**Example chain** for `kvm-ocp-virt`:
```
wave 1: openshift-local-storage (operator)
wave 2: openshift-data-foundation (operator) + openshift-virtualization (operator)
wave 3: openshift-data-foundation (instance)
wave 4: openshift-virtualization (instance)
```

---

## Prune and SelfHeal Decision Guide

| Scenario | `prune` | `selfHeal` | Reason |
|---|---|---|---|
| Stateless operators (Pipelines, Gitops) | `true` | `true` | Safe to delete and recreate |
| Storage operators (ODF, LSO) | `false` | `true` | Deleting storage destroys data |
| Stateful instances (StorageCluster) | `false` | `true` | Never auto-delete storage CRs |
| Root app-of-apps | `true` | `true` | Controls Application objects, not data |
| ACM hub | `false` | `true` | MCH deletion triggers cluster teardown |
| Virtualization instance | `false` | `true` | HyperConverged manages VM lifecycle |

**Default for new operators:** `prune: false, selfHeal: true`

---

## Testing Kustomize Overlays

Before committing or applying, always verify:

```bash
# Build and inspect output (no cluster access required):
oc kustomize gitops/cluster-config/<operator>/operator/overlays/<channel>/

# Check for the placeholder channel (should not appear in output):
oc kustomize gitops/cluster-config/<operator>/operator/overlays/<channel>/ \
  | grep "patch-me-see-overlays-dir"
# Expected: no output (channel was replaced by the patch)

# Diff against what's on the cluster:
oc diff -k gitops/cluster-config/<operator>/operator/overlays/<channel>/
```

---

## Relationship to gitops-catalog

This repo's pattern is compatible with both:
- **`redhat-cop/gitops-catalog`** — upstream community catalog (90+ operators)
- **`tosin2013/gitops-catalog`** — Tosin's fork with OpenShift-specific additions

See [`docs/gitops-catalog.md`](gitops-catalog.md) for how to use these catalogs as a
reference or starting point when adding new operators.

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Hardcoding channel in `base/subscription.yaml` | Channel can't be overridden per OCP version | Move channel to overlay's `patch-channel.yaml` |
| Pointing ArgoCD at `base/` instead of `overlays/<channel>/` | Applies placeholder channel `patch-me-see-overlays-dir` to cluster | Always point at an overlay path |
| Forgetting `namespace:` in overlay `kustomization.yaml` | Resources land in wrong namespace | Add `namespace:` matching the operator's target namespace |
| Using `oc create` instead of `oc apply` for Application YAML | Fails on second run with "already exists" | Use `oc apply -f` |
| Applying two profiles at once | Both create `cluster-config` Application → conflict | Only one profile per cluster at a time |
| Wrong sync wave order | Instance applies before operator is Ready | Operator = wave 1-2, instance = wave 3+ |
