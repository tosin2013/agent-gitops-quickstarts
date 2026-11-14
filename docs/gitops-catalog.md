# gitops-catalog Integration

## What is the gitops-catalog?

The **gitops-catalog** is a community collection of Kustomize-based operator configurations
for OpenShift. It uses the same base/overlay pattern as this repo, making it a great
reference or starting point when adding a new operator.

There are two relevant repos:

| Repo | Description |
|---|---|
| [`redhat-cop/gitops-catalog`](https://github.com/redhat-cop/gitops-catalog) | Upstream community catalog — 90+ operators, Red Hat Community of Practice |
| [`tosin2013/gitops-catalog`](https://github.com/tosin2013/gitops-catalog) | Fork with OpenShift-specific additions and `scripts/automate_operators.sh` |

Both follow the same directory layout: one top-level directory per operator, each with
`base/` and `overlays/` subdirectories — identical to the pattern used in this repo.

---

## When to Check the gitops-catalog

**Before writing a new operator config from scratch**, check the gitops-catalog:

```bash
# Clone Tosin's fork (includes extra scripts):
git clone --depth=1 https://github.com/tosin2013/gitops-catalog.git /tmp/gitops-catalog

# Search for your operator:
ls /tmp/gitops-catalog/ | grep -i <operator-keyword>
```

If the operator is in the catalog, copy that base as your starting point — it already has
the correct Namespace, OperatorGroup, and Subscription structure. You'll only need to:
1. Adjust the `repoURL` or inline the content
2. Set `channel: patch-me-see-overlays-dir` in the base Subscription
3. Create your version-specific overlay

---

## How to Use the gitops-catalog as a Reference

### Option A: Copy locally (recommended for production)

Copy the operator directory into this repo's `gitops/cluster-config/`:

```bash
OPERATOR="<operator-directory-name>"  # e.g. openshift-data-foundation

# Copy from Tosin's fork:
cp -r /tmp/gitops-catalog/$OPERATOR \
  gitops/cluster-config/$OPERATOR

# Review and adapt:
# 1. Set channel to placeholder in base/
sed -i 's/channel: .*/channel: patch-me-see-overlays-dir/' \
  gitops/cluster-config/$OPERATOR/operator/base/*-subscription.yaml

# 2. Create your overlay:
mkdir -p gitops/cluster-config/$OPERATOR/operator/overlays/stable-4.22
# ... add kustomization.yaml and patch-channel.yaml

# 3. Verify:
oc kustomize gitops/cluster-config/$OPERATOR/operator/overlays/stable-4.22/
```

**Why copy instead of referencing remotely?**
Remote Kustomize references (`resources: https://github.com/redhat-cop/gitops-catalog/...`)
work but have downsides in production:
- Requires cluster internet access at sync time
- Catalog changes can break your deployment without warning
- ArgoCD can't cache or audit remote references as reliably

### Option B: Remote reference (for evaluation/testing only)

```bash
# Kustomize can build directly from GitHub:
oc kustomize https://github.com/redhat-cop/gitops-catalog/openshift-pipelines-operator/overlays/latest

# This is useful to test before copying:
oc kustomize https://github.com/tosin2013/gitops-catalog/openshift-data-foundation-operator/operator/overlays/stable-4.19
```

---

## What's in `tosin2013/gitops-catalog` Beyond the Upstream

Tosin's fork adds:
- `scripts/automate_operators.sh` — a script to dump all operator package manifests to `operator_info.txt`
- `operator_info.txt` — pre-dumped OCP operator metadata (channels, namespaces, install modes)

The `operator_info.txt` is useful for quickly looking up channel names without needing a live cluster:

```bash
grep -A 10 "openshift-data-foundation" /tmp/gitops-catalog/operator_info.txt
```

---

## Catalog Pattern vs This Repo

| Aspect | gitops-catalog | agent-gitops-quickstarts |
|---|---|---|
| Scope | Individual operator configs | End-to-end deployment profiles |
| ArgoCD Applications | Not included | Full `gitops/cluster-config/apps/<profile>/` layer |
| Platform overlays | Minimal (generic) | Platform-specific (AWS, GCP, Azure, KVM, etc.) |
| AI skills | None | 11 SKILL.md files |
| Self-learning | None | `--learn` flag + learn-environment agent |
| GitOps bootstrap | Not included | `deploy.sh` + `configure-repo.sh` |

**Recommended workflow:**
1. Check gitops-catalog for the operator base config
2. Copy it into this repo
3. Add version-specific overlays for OCP 4.9–4.22 / 5.0
4. Add platform-specific instance overlays (AWS, GCP, bare-metal, etc.)
5. Add ArgoCD Application YAML to the relevant profile
6. Document in `llm.txt`

---

## Cross-Referencing When Adding a New Operator

```bash
# 1. Check gitops-catalog for existing config
ls /tmp/gitops-catalog/ | grep -i <keyword>

# 2. Check this repo (maybe it's already here)
ls gitops/cluster-config/ | grep -i <keyword>

# 3. Check the cluster's available operators
oc get packagemanifest -n openshift-marketplace | grep -i <keyword>

# 4. Get channel info
oc describe packagemanifest <name> -n openshift-marketplace | grep -E "Channel Name|Current CSV"
```

Then follow the [`create-kustomize-operator`](../gitops/skills/create-kustomize-operator/SKILL.md) skill.

---

## Contributing Back to the Catalog

If you create a new operator config in this repo that would benefit the community,
consider contributing it back upstream:

1. Fork `redhat-cop/gitops-catalog`
2. Add your operator directory (base + overlays)
3. Submit a PR

This helps the whole OpenShift community and ensures the pattern stays in sync.
