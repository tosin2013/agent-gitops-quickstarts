---
name: bootstrap-gitops
description: Bootstrap OpenShift GitOps (ArgoCD) on a fresh cluster using gitops/deploy.sh
version: "1.0"
compatibility:
  ocp: ">=4.9"
  tools: ["oc", "bash"]
triggers:
  - "bootstrap gitops"
  - "install argocd"
  - "install openshift gitops"
  - "set up gitops"
  - "deploy argocd"
---

# bootstrap-gitops

## Overview

Installs OpenShift GitOps (ArgoCD) on a fresh OpenShift cluster using the repo's `deploy.sh`
bootstrap script. This is always the first skill to run — all other Day 2 skills depend on
ArgoCD being present and healthy.

## Prerequisites

- OpenShift cluster running OCP 4.12+
- `oc` CLI authenticated with cluster-admin: `oc whoami`
- Git repo cloned locally (or a repoURL accessible from the cluster)

## Quick Diagnostics

```bash
# Check cluster access and version
oc whoami
oc version

# Check if gitops is already installed
oc get namespace openshift-gitops 2>/dev/null && echo "ALREADY INSTALLED" || echo "NOT YET INSTALLED"

# Check if ArgoCD is running (if installed)
oc get pods -n openshift-gitops --no-headers 2>/dev/null | grep -v Running | grep -v Completed || echo "All pods healthy"

# Check GitOps operator subscription
oc get subscription -n openshift-gitops 2>/dev/null
```

## Repo URL Decision (Answer Before Starting)

**Where is your Git repo?** The ArgoCD Applications hardcode the original GitHub URL.
You must decide before bootstrapping:

| Situation | Action |
|---|---|
| Using original GitHub repo (read-only, testing) | No change needed |
| Forked to your GitHub org | Run `./gitops/configure-repo.sh https://github.com/YOUR_ORG/sno-quickstarts.git` |
| Using self-hosted Gitea on OpenShift | Run `./gitops/setup-gitea.sh` (auto-deploys Gitea + configures) |
| Using GitLab / other self-hosted Git | Run `./gitops/configure-repo.sh https://your-git-server/repo.git` |

If you don't configure the repo URL, ArgoCD will pull from the **original GitHub repo**
which you likely cannot push your customizations to.

## Steps

### Step 1: Clone the repository

```bash
git clone https://github.com/tosin2013/sno-quickstarts.git
cd sno-quickstarts
```

### Step 1b: Configure your repo URL (if not using the original GitHub repo)

```bash
# For a GitHub fork:
./gitops/configure-repo.sh https://github.com/YOUR_ORG/sno-quickstarts.git

# For self-hosted Gitea on OpenShift (fully automated):
./gitops/setup-gitea.sh

# For GitLab or other:
./gitops/configure-repo.sh https://gitlab.company.com/team/sno-quickstarts.git

# Then push your repo to that remote before proceeding
git push <your-remote> main
```

### Step 2: Authenticate to your cluster

```bash
oc login https://api.<cluster>.<domain>:6443
oc whoami  # verify
```

### Step 3: Run the bootstrap script

```bash
./gitops/deploy.sh
```

This script:
1. Creates the `openshift-gitops` namespace
2. Applies the GitOps operator Subscription and ArgoCD CR
3. Waits 30 seconds for the operator to initialize
4. Re-applies to ensure the ArgoCD instance is configured

### Step 4: Wait for ArgoCD to be ready

```bash
oc rollout status deployment/openshift-gitops-server -n openshift-gitops --timeout=300s
```

### Step 5: Verify ArgoCD is healthy

```bash
oc get pods -n openshift-gitops
oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.status.phase}'
```

Expected output: all pods `Running`, status `Available`.

### Step 5b: Add repo credentials if using a private repo

```bash
oc create secret generic repo-creds -n openshift-gitops \
  --from-literal=username=<git-user-or-org> \
  --from-literal=password=<personal-access-token> \
  --from-literal=url=<your-repo-url>
oc label secret repo-creds -n openshift-gitops argocd.argoproj.io/secret-type=repository
```

Skip this step if using a public repo (GitHub public fork or public Gitea repo).

### Step 6: Get the ArgoCD console URL

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

Log in with OpenShift OAuth credentials.

## Verification

```bash
# All ArgoCD pods running
oc get pods -n openshift-gitops

# ArgoCD route accessible
oc get route -n openshift-gitops

# No sync errors (no applications yet, but server should be healthy)
oc get application -n openshift-gitops
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| ArgoCD apps stuck with "authentication required" or "repository not found" | Private repo without credentials, or wrong repoURL | Add repo credentials secret (see Step 5b); verify URL with `./configure-repo.sh --dry-run` |
| Apps sync from wrong repo (original GitHub instead of your fork) | forgot to run `configure-repo.sh` | Run `./gitops/configure-repo.sh <your-url>`, push to your repo, force ArgoCD refresh |
| `namespace "openshift-gitops" already exists` | Namespace pre-exists | Safe to continue; run `oc apply -k gitops/cluster-config/openshift-gitops` directly |
| Pod `openshift-gitops-server` CrashLoopBackOff | RBAC ClusterRoleBinding not created | Apply `oc apply -f gitops/cluster-config/openshift-gitops/rbac.yaml` |
| `oc create -k` fails with `no matches for kind "ArgoCD"` | GitOps operator CRD not yet registered | Wait 2 minutes and re-run `oc apply -k gitops/cluster-config/openshift-gitops` |
| Subscription stuck in `UpgradePending` | Manual installPlan approval required | `oc get installplan -n openshift-gitops` then approve: `oc patch installplan <name> -n openshift-gitops --type merge -p '{"spec":{"approved":true}}'` |
| `Error from server: timeout` during rollout | Cluster nodes under resource pressure | Check node capacity: `oc describe nodes | grep -A5 Allocated` |

## Related Skills

- [[deploy-profile]] — Run after bootstrapping to deploy a cluster profile
- [[troubleshoot-argocd]] — Use if ArgoCD fails to sync after bootstrapping
