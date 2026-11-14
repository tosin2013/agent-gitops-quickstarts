# End-to-End Guide — agent-gitops-quickstarts

This guide walks you through a complete Day 2 OpenShift configuration from a freshly
provisioned cluster to a fully configured environment with storage, operators, and workloads.

**Time to complete:** 30–90 minutes depending on cluster size and operators selected.

---

## Before You Start

### Prerequisites

- OpenShift cluster 4.9+ running (any platform)
- `oc` CLI installed and authenticated with cluster-admin
- `git` installed on the machine where you run these commands
- For multi-node storage: 3+ worker nodes with dedicated unformatted local disks

```bash
# Verify cluster access
oc whoami
oc get nodes
oc version | grep "Server Version"
```

### Where did your cluster come from?

- **Provisioned with [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install)?**
  You're in the right place — this is the Day 2 counterpart.
- **Provisioned with the Assisted Installer or IPI?**
  Same flow applies.
- **ROSA, ARO, or other managed OCP?**
  Some steps differ (managed storage classes instead of ODF). Use the cloud-specific profile
  (`aws-odf-deployment`, `gcp-odf-deployment`) and skip the infra-node labeling steps.

---

## Step 0 — Get the Repo

```bash
git clone https://github.com/tosin2013/agent-gitops-quickstarts.git
cd agent-gitops-quickstarts
```

---

## Step 1 — Point to Your Git Repository

ArgoCD will pull manifests from a Git repository. The default points to the original
GitHub repo. **If you plan to customize manifests, point to your own fork first.**

```bash
# Option A: GitHub fork
./gitops/configure-repo.sh https://github.com/YOUR_ORG/agent-gitops-quickstarts.git

# Option B: Self-hosted Gitea on OpenShift (air-gapped / no GitHub access)
./gitops/setup-gitea.sh

# Option C: GitLab, Bitbucket, or other
./gitops/configure-repo.sh https://your-git-server/your-org/agent-gitops-quickstarts.git

# Then push to your remote:
git push <your-remote> main
```

Skip this step if you're evaluating with the original GitHub repo (read-only is fine for testing).

---

## Step 2 — Bootstrap ArgoCD

Install OpenShift GitOps (ArgoCD) on the cluster.

```bash
cd gitops
./deploy.sh
```

**What this does:**
1. Creates the `openshift-gitops` namespace
2. Applies the GitOps operator Subscription
3. Applies the ArgoCD CR with OpenShift OAuth integration
4. Waits ~30 seconds for the operator to initialize

**Verify:**
```bash
oc get pods -n openshift-gitops | grep repo-server
# Expected: openshift-gitops-repo-server-* Running

oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
# Open this URL in a browser — log in with OpenShift credentials
```

> **Using AI skills?** Say: *"bootstrap gitops on my cluster"* — the `bootstrap-gitops` skill
> handles this with idempotency checks and waits.

---

## Step 3 — Choose Your Path

| Cluster type | Recommended path |
|---|---|
| **Multi-node with local disks** (bare-metal, KVM, Red Hat Labs) | [Path A — Lab/KVM](#path-a--labkvm-multi-node-with-local-storage) |
| **Cloud cluster** (AWS, GCP, Azure) | [Path B — Cloud](#path-b--cloud-aws-gcp-azure) |
| **SNO (Single Node OpenShift)** | [Path C — SNO](#path-c--single-node-openshift-sno) |
| **RHACM hub cluster** | [Path D — RHACM Hub](#path-d--rhacm-hub) |

---

## Path A — Lab/KVM: Multi-Node with Local Storage

For bare-metal, KVM/libvirt, Equinix Metal, or Red Hat Labs clusters with local disks.

### A1. Run the lab orchestrator

```bash
cd agent-gitops-quickstarts

# Dry-run first (see what would happen):
./gitops/configure-redhat-labs.sh --dry-run \
  --configure-infra-nodes \
  --configure-storage \
  --nodes worker-0,worker-1,worker-2

# Apply (auto-discovers nodes if --nodes not supplied):
./gitops/configure-redhat-labs.sh \
  --configure-infra-nodes \
  --configure-storage \
  --profile kvm-ocp-virt \
  --ocp-version 4.22 \
  --learn
```

**What `--learn` does:** writes a sanitized execution journal that the AI `learn-environment`
agent uses to create overlays and skill improvements for your cluster type.

### A2. Wait for storage to be ready

```bash
# StorageCluster takes 10–20 minutes to reach Ready state:
watch oc get storagecluster -n openshift-storage

# When phase = Ready:
oc get storageclass | grep -E "ceph|ocs"
```

### A3. Verify the profile is synced

```bash
oc get application -n openshift-gitops
# All apps should show: Synced / Healthy
```

---

## Path B — Cloud: AWS / GCP / Azure

For clusters running on cloud infrastructure where storage uses cloud PVs.

### B1. Apply the cloud profile directly

```bash
# AWS:
oc apply -f gitops/apps/aws-odf-deployment/cluster-config.yaml

# GCP:
oc apply -f gitops/apps/gcp-odf-deployment/cluster-config.yaml

# Azure (uses managed-premium storage class):
# No dedicated profile yet — use aws-odf-deployment as a base and customize
# the ODF instance overlay: gitops/cluster-config/openshift-data-foundation-operator/instance/overlays/azure/
```

### B2. Watch ArgoCD sync

```bash
watch oc get application -n openshift-gitops
# Wait for all apps: SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

### B3. For cloud clusters — label storage nodes if using ODF

ODF on cloud still needs node labels to know which nodes host OSD pods:

```bash
# Label 3 worker nodes:
for node in $(oc get nodes -l node-role.kubernetes.io/worker \
  --no-headers -o name | head -3 | sed 's|node/||'); do
  oc label node $node cluster.ocs.openshift.io/openshift-storage=""
done
```

---

## Path C — Single Node OpenShift (SNO)

SNO uses ODF-LVM (no Ceph) or hostpath-provisioner — not full ODF.

### C1. Deploy the SNO profile

```bash
# SNO + OpenShift Virtualization (uses hostpath-provisioner):
oc apply -f gitops/apps/sno-ocp-virt/cluster-config.yaml

# SNO + ODF-LVM + Pipelines:
oc apply -f gitops/apps/standard-sno-deployment/cluster-config.yaml
```

### C2. Watch sync

```bash
oc get application -n openshift-gitops -o wide
```

> **Using AI skills?** Say: *"deploy the sno-ocp-virt profile"* — the `deploy-profile` skill
> handles the full flow including waiting for each operator before the next.

---

## Path D — RHACM Hub

For clusters that will manage other clusters (hub + spoke topology).

### D1. Deploy the RHACM hub profile

```bash
# Basic RHACM hub:
oc apply -f gitops/apps/acm-gitops-deployment/cluster-config.yaml

# Full bare-metal hub (RHACM + AAP + Dev Spaces):
oc apply -f gitops/apps/baremetal-rhacm-hub/cluster-config.yaml
```

### D2. Wait for MultiClusterHub

```bash
# MCH takes 10–15 minutes:
watch oc get mch -n open-cluster-management
# Phase should reach: Running
```

### D3. Add spoke clusters via ZTP (optional)

After RHACM is running, follow the [`configure-ztp` skill](../gitops/skills/configure-ztp/SKILL.md)
to provision bare-metal spoke clusters.

---

## Step 4 — Verify Everything

Regardless of path:

```bash
# All ArgoCD apps synced and healthy
oc get application -n openshift-gitops

# Check storage (if ODF was installed)
oc get storagecluster -n openshift-storage -o wide
oc get storageclass

# Check operators installed
oc get csv -A | grep -v "Succeeded"  # should be empty if all healthy

# Check any pods in error
oc get pods -A | grep -v Running | grep -v Completed | grep -v Succeeded
```

**If anything is out of sync**, use the `troubleshoot-argocd` skill:
> *"ArgoCD is not syncing the openshift-data-foundation-operator app"*

---

## Step 5 — Self-Learning (Optional but Recommended)

If you used `--learn` during setup, trigger the AI to improve the repo for your cluster type:

```bash
# In Claude Code, type:
# "review the latest learning at gitops/learnings/ and update skills"
```

The `learn-environment` agent reads your execution journal, checks for coverage gaps,
and creates or updates overlays, profiles, and skill documentation automatically.

Before it commits anything, it runs `./gitops/sanitize-journal.sh` to scrub sensitive
data (cluster domain, node names) from the journal.

---

## Common Issues

| Symptom | Skill to use | Quick fix |
|---|---|---|
| ArgoCD apps stuck OutOfSync | `troubleshoot-argocd` | Force refresh: `oc annotate app <name> -n openshift-gitops argocd.argoproj.io/refresh=normal` |
| StorageCluster not reaching Ready | `install-odf` | Check node labels + disk availability |
| Apps pulling from wrong repo | `bootstrap-gitops` | Run `./gitops/configure-repo.sh <your-url>` |
| Operator CSV shows Failed | `troubleshoot-argocd` | Check OCP version matches overlay channel |
| ArgoCD can't authenticate to private repo | `bootstrap-gitops` | Create `repo-creds` secret in `openshift-gitops` namespace |

---

## AI Skills Reference

Install skills once, then trigger them in Claude Code by typing natural language:

```bash
./gitops/skills/install-skills.sh --all
```

| What you want to do | Say this in Claude Code |
|---|---|
| Install ArgoCD | *"bootstrap gitops on my cluster"* |
| Install ODF storage | *"install ODF on OCP 4.22"* |
| Install OpenShift Virtualization | *"install OpenShift Virtualization"* |
| Install RHACM | *"install RHACM hub"* |
| Deploy a full profile | *"deploy the kvm-ocp-virt profile"* |
| Fix sync failures | *"ArgoCD not syncing"* |
| Multi-node lab setup | *"configure lab environment"* |
| Provision ZTP spokes | *"configure ZTP spoke cluster"* |

---

## Repository Structure Cheat Sheet

```
gitops/
  deploy.sh                      # Step 2: bootstrap ArgoCD
  configure-repo.sh              # Step 1: set your Git repo URL
  configure-redhat-labs.sh       # Path A: multi-node lab orchestrator
  setup-gitea.sh                 # Optional: self-hosted Git on OpenShift
  apps/
    <profile>/cluster-config.yaml  # Apply this to deploy a profile
  cluster-config/
    apps/<profile>/              # Per-operator ArgoCD Applications
    <operator>/operator/overlays/<ocp-version>/  # OCP version-specific channels
    <operator>/instance/overlays/<platform>/     # Platform-specific instances
  skills/
    README.md                    # Skills overview (you are here)
    <skill-name>/SKILL.md        # Individual skill instructions
    install-skills.sh            # Install skills into Claude Code
  learnings/                     # Self-learning execution journals
```
