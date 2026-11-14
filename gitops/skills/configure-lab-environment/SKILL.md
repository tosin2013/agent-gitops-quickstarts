---
name: configure-lab-environment
description: Configure infra nodes, local storage, ODF, and deploy a profile on any multi-node cluster (bare-metal, KVM, Equinix, Red Hat Labs, vSphere)
version: "1.0"
compatibility:
  ocp: ">=4.9"
  platforms: ["bare-metal", "kvm", "equinix", "vsphere", "red-hat-labs"]
  topology: "3+ worker nodes with local disks"
triggers:
  - "configure lab environment"
  - "set up 3-node cluster"
  - "label infra nodes"
  - "configure storage nodes"
  - "Red Hat Labs setup"
  - "KVM cluster setup"
  - "baremetal cluster storage setup"
  - "configure local storage"
  - "configure-redhat-labs"
---

# configure-lab-environment

## Overview

Configures a multi-node OpenShift cluster for Day 2 GitOps operations using the
`configure-redhat-labs.sh` orchestrator script. The full flow is:

1. Bootstrap ArgoCD (OpenShift GitOps)
2. Label worker nodes as infra/storage nodes
3. Install Local Storage Operator + discover local disks
4. Install ODF (OpenShift Data Foundation / Ceph)
5. Deploy a cluster profile via ArgoCD

This skill works on **any platform** (bare-metal, KVM/libvirt, Equinix Metal, VMware vSphere,
Red Hat Labs) and **any node naming convention** — node names are auto-discovered or supplied
via `--nodes`.

With `--learn`, the script writes an execution journal that the **[[learn-environment]]**
agent reads to automatically improve skills, overlays, and profiles for new environment types.

## Prerequisites

- OpenShift cluster running OCP 4.9+
- `oc` CLI authenticated with cluster-admin: `oc whoami`
- Cluster has 3+ worker nodes with dedicated unformatted local disks
- Repo configured to point at your Git server (run `./configure-repo.sh` if needed)

## Quick Diagnostics

```bash
# Check cluster access and node list
oc whoami
oc get nodes -o wide

# Check which nodes have local disks (look for /dev/sd* or /dev/nvme*)
oc debug node/<node-name> -- chroot /host lsblk

# Check if ArgoCD is already running
oc get pods -n openshift-gitops | grep repo-server

# Check storage cluster status
oc get storagecluster -n openshift-storage 2>/dev/null || echo "Not installed"
oc get localvolumeset -n openshift-local-storage 2>/dev/null || echo "Not installed"

# Check all ArgoCD applications
oc get application -n openshift-gitops
```

## Steps

### Step 0: Repo URL check

Ensure ArgoCD will pull from your repo (not the original GitHub):

```bash
# Check what URL is currently configured in profile YAMLs:
grep -r "repoURL" gitops/apps/ | head -3

# If it shows the original GitHub URL and you're using a fork or Gitea:
./gitops/configure-repo.sh https://your-repo-url.git
git push <your-remote> main
```

### Step 1: Discover your node names

```bash
# List all worker nodes:
oc get nodes -l node-role.kubernetes.io/worker --no-headers \
  -o custom-columns='NAME:.metadata.name'

# If no worker label, list all non-master nodes:
oc get nodes --no-headers | grep -v master
```

Note the node names — you'll pass them to the script or let it auto-discover.

### Step 2: Run the orchestrator (all-in-one)

```bash
cd /path/to/sno-quickstarts

# Auto-discover nodes + current OCP version + self-learning:
./gitops/configure-redhat-labs.sh \
  --configure-infra-nodes \
  --configure-storage \
  --profile kvm-ocp-virt \
  --learn

# Or with explicit nodes:
./gitops/configure-redhat-labs.sh \
  --configure-infra-nodes \
  --configure-storage \
  --nodes worker-0,worker-1,worker-2 \
  --ocp-version 4.22 \
  --profile kvm-ocp-virt \
  --learn
```

Flags:
- `--configure-infra-nodes` — labels nodes + patches registry + ingress controller
- `--configure-storage` — LSO + ODF with auto-generated node overlay
- `--odf-instance-overlay` — override which ODF StorageCluster overlay to use
- `--learn` — write execution journal for self-improvement

### Step 3: Dry-run first (recommended)

```bash
./gitops/configure-redhat-labs.sh \
  --configure-infra-nodes \
  --configure-storage \
  --nodes lab-worker-0,lab-worker-1,lab-worker-2 \
  --dry-run
```

### Step 4: Trigger self-learning (after success)

```bash
# After a successful --learn run, ask the agent to improve the repo:
# In Claude Code, type: "review the latest learning at gitops/learnings/ and update skills"
# This invokes the learn-environment agent.
```

### Step 5: Verify the full setup

```bash
# All ArgoCD apps synced and healthy
oc get application -n openshift-gitops

# StorageCluster ready (may take 10-20 min)
oc get storagecluster -n openshift-storage -o wide

# Storage classes created by ODF
oc get storageclass | grep -E "ceph|ocs"

# Infra nodes labeled
oc get nodes -l node-role.kubernetes.io/infra
```

## Known Working Configurations

| Environment | Platform | Node Pattern | OCP | ODF Overlay | Profile |
|---|---|---|---|---|---|
| Red Hat Labs (3-node) | None | `lab-worker-N` | 4.22 | equinix-cnv | kvm-ocp-virt |
| Equinix Metal | None | equinix-* | 4.22 | equinix-cnv | equinix-cnv-virtualization |
| Generic KVM | None | worker-N | 4.22 | bare-metal | kvm-ocp-virt |

*This table is updated automatically by the [[learn-environment]] agent after each `--learn` run.*

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| `stable-4.22` overlay not found | Wrong `--ocp-version` or overlay missing | Run `ls gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/`; use a version that exists |
| Nodes not labeled (node not found) | Wrong node names or nodes have different names | Run `oc get nodes` to get exact names; pass with `--nodes` |
| StorageCluster stuck in Progressing | OSD pods can't find disks | Verify nodes have unformatted disks: `oc debug node/<n> -- chroot /host lsblk` |
| `oc create -k` fails on LSO instance | LSO operator not yet fully installed | Increase `--timeout` or wait and re-run with `--configure-storage` only |
| ArgoCD apps sync from wrong repo | `configure-repo.sh` not run | Run `./gitops/configure-repo.sh <your-url>` and push |
| IngressController patch fails | Infra nodes have no `NoSchedule` taint yet | Apply taint manually or omit the ingress patch step |
| `--learn` journal not written | LEARNINGS_DIR not writable | Check `gitops/learnings/` directory exists and is writable |

## Related Skills

- [[bootstrap-gitops]] — ArgoCD bootstrap (called automatically by this script)
- [[install-odf]] — ODF installation details and platform-specific notes
- [[deploy-profile]] — ArgoCD profile deployment
- [[troubleshoot-argocd]] — ArgoCD sync failures
- [[learn-environment]] — Post-run self-learning agent
