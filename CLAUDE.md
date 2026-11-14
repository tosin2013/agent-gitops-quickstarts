# CLAUDE.md — agent-gitops-quickstarts

## Project Overview

**agent-gitops-quickstarts** provides GitOps-driven Day 2 configuration for **any OpenShift
deployment** using ArgoCD (OpenShift GitOps) + Kustomize. It is the logical continuation of:
- **Day 1**: [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install) — cluster provisioning
- **Day 2**: this repo — operator installation, cluster configuration, platform setup

**Supported OCP versions**: 4.9 through 4.22 and 5.0 (operator overlays exist for every minor version; 4.22 is current latest 4.x)

**Supported platforms**: bare-metal, KVM/libvirt, VMware vSphere, Equinix Metal, AWS, GCP,
Azure, and any platform that runs OpenShift — SNO, 3-node compact, standard HA, and
multi-cluster (ACM hub + ZTP spokes).

For a complete AI-readable reference, see `llm.txt`.

## Repository Structure

```
agent-gitops-quickstarts/
  LICENSE                         # Apache 2.0
  llm.txt                         # Complete AI reference (bootstrap, operators, profiles)
  AGENTS.md                       # Universal agent guardrails (read before making changes)
  gitops/
    deploy.sh                     # Step 1: bootstrap ArgoCD on a fresh cluster
    apps/                         # Profile entry-points (13 profiles)
      <profile-name>/
        cluster-config.yaml       # ArgoCD Application — apply this to deploy the profile
    cluster-config/               # Operator manifests
      apps/                       # Per-profile ArgoCD Application sets
        <profile-name>/           # One .yaml per operator in the profile
      <operator-name>/            # Kustomize tree for one operator
        operator/base/            # Namespace, OperatorGroup, Subscription (placeholder channel)
        operator/overlays/<chan>/ # Channel-specific patch (patch-channel.yaml)
        instance/base/            # CRD instance (StorageCluster, HyperConverged, etc.)
        instance/overlays/<plat>/ # Platform-specific instance config
    skills/                       # AI skill definitions
      install-skills.sh           # Install skills: --all, --list, --skill <name>
      <skill-name>/SKILL.md       # Skill definition
```

## Repository Configuration (Do This First)

All ArgoCD Application YAMLs hardcode the original GitHub URL. If you're using your own
fork, Gitea, GitLab, or any other Git server, run this **before bootstrapping**:

```bash
# See what changes (111 files):
./gitops/configure-repo.sh --dry-run https://your-repo-url.git

# Apply it:
./gitops/configure-repo.sh https://your-repo-url.git

# Push to your repo:
git push <your-remote> main
```

### Self-hosted Gitea on OpenShift (air-gapped / no GitHub access)

```bash
# Fully automated: deploy Gitea + push repo + reconfigure all URLs
./gitops/setup-gitea.sh
```

This runs `deploy-gitea.sh` from `tosin2013/openshift-demos`, creates a Gitea instance
at `https://gitea-gitea.apps.<cluster>.<domain>`, and updates all repoURLs automatically.

### ArgoCD repo credentials (private repos only)

```bash
oc create secret generic repo-creds -n openshift-gitops \
  --from-literal=username=<user> \
  --from-literal=password=<token> \
  --from-literal=url=<repo-url>
oc label secret repo-creds -n openshift-gitops argocd.argoproj.io/secret-type=repository
```

## Bootstrap Flow

```bash
# 1. Authenticate to your cluster
oc login https://api.<cluster>.<domain>:6443

# 2. Bootstrap OpenShift GitOps (ArgoCD)
./gitops/deploy.sh

# 3. Deploy a cluster profile
oc apply -f gitops/apps/<profile-name>/cluster-config.yaml
```

ArgoCD then creates per-operator Applications and syncs all resources from Git.

## Kustomize Base/Overlay Pattern

Every operator uses this pattern:

```
base/kustomization.yaml     → lists Namespace, OperatorGroup, Subscription resources
base/<op>-subscription.yaml → channel: patch-me-see-overlays-dir  (never commit as-is)

overlays/<channel>/kustomization.yaml  → resources: [../../base], patches: [patch-channel.yaml]
overlays/<channel>/patch-channel.yaml → replaces channel with the actual value
```

**Example** — deploy ODF for OCP 4.19:
```bash
oc apply -k gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/stable-4.19
```

## Profile Catalog

| Profile | Platform | Use Case |
|---|---|---|
| `sno-ocp-virt` | Any (SNO) | SNO + OpenShift Virtualization |
| `standard-sno-deployment` | Any (SNO) | SNO + ODF + Pipelines |
| `kvm-ocp-virt` | KVM/libvirt | KVM VMs + ODF + Virtualization |
| `aws-odf-deployment` | AWS | AWS cluster + ODF (gp2) |
| `gcp-odf-deployment` | GCP | GCP cluster + ODF (standard-csi) |
| `vmware-odf-deployment` | vSphere | VMware + ODF |
| `equinix-cnv-virtualization` | Equinix Metal | Bare-metal + Virtualization |
| `equinix-developer-env` | Equinix Metal | Bare-metal developer environment |
| `acm-gitops-deployment` | Any | RHACM hub cluster |
| `aap-instance` | Any | Ansible Automation Platform |
| `developer-env` | Any | Dev tools: AAP + Dev Spaces |
| `baremetal-rhacm-hub` | Bare-metal | Full bare-metal hub |
| `device-edge-demos` | Any | Device Edge + Quay |
| `kafka-plus-db` | Any | Kafka + PostgreSQL |
| `middleware-ocpv` | Any | Middleware + OCP Virt |
| `rhel-edge-management` | Any | RHEL Edge management |

## How to Add a New Operator

1. Copy a similar existing operator directory as a starting point
2. Set `channel: patch-me-see-overlays-dir` in the base Subscription
3. Create `operator/overlays/<channel>/` with `kustomization.yaml` and `patch-channel.yaml`
4. Verify: `oc kustomize operator/overlays/<channel>/`
5. Add an entry to `llm.txt` under the appropriate category
6. Optionally add it to a profile in `gitops/cluster-config/apps/<profile>/`

## How to Add a New OCP Version Overlay

1. Look up the channel name in Red Hat documentation (`docs.redhat.com`)
2. Create `operator/overlays/<new-channel>/`
3. Copy `kustomization.yaml` from an adjacent overlay (change nothing except the patch path if needed)
4. Create `patch-channel.yaml` with the correct channel value
5. Verify: `oc kustomize operator/overlays/<new-channel>/`
6. Update the OCP Version Matrix table in `llm.txt`

## Platform Storage Selection

| Platform | Storage Type | ODF Instance Overlay |
|---|---|---|
| AWS | ODF + EBS (gp2) | `instance/overlays/aws` |
| GCP | ODF + Persistent Disk (standard-csi) | `instance/overlays/gcp` |
| Azure | ODF + Managed Disk (managed-premium) | `instance/overlays/azure` |
| VMware vSphere | ODF + vSphere datastore | `instance/overlays/vsphere` |
| Bare-metal / Equinix | ODF + local-storage | `instance/overlays/bare-metal` |
| KVM / libvirt | ODF + local-storage | `instance/overlays/kvm` |
| SNO (any) | ODF-LVM (no Ceph) or hostpath-provisioner | `odf-lvm-operator/instance/overlays/` |

## OCP 5.0 Notes

OCP 5.0 overlays exist for ODF (`stable-5.0`), Local Storage (`stable-5.0`), RHACM
(`stable-5.0`), OpenShift Virtualization (`stable`), and Pipelines (`latest-5.0`).

OCP 5.0 uses OLM v1 (`ClusterExtension` API) but classic `Subscription` remains supported.
ODF on OCP 5.0 requires RHCOS 10 and x86-64-v3+ CPU microarchitecture.

## Skills Reference

```
$ ./gitops/skills/install-skills.sh --list
```

| Skill | Description |
|---|---|
| `bootstrap-gitops` | Bootstrap OpenShift GitOps (ArgoCD) on a fresh cluster |
| `install-odf` | Install OpenShift Data Foundation (ODF/Ceph) |
| `install-virtualization` | Install OpenShift Virtualization (CNV/KubeVirt) |
| `install-acm` | Install Red Hat Advanced Cluster Management hub |
| `configure-ztp` | Configure ZTP spoke cluster provisioning |
| `install-aap` | Install Ansible Automation Platform |
| `deploy-profile` | Deploy a full cluster profile via ArgoCD |
| `troubleshoot-argocd` | Diagnose and fix ArgoCD sync failures |
| `configure-lab-environment` | Configure infra nodes + local storage + ODF + profile on any multi-node cluster |
| `create-kustomize-operator` | Scaffold a new operator (base + overlays + ArgoCD Application YAML) |
| `manage-argocd-apps` | Create and manage ArgoCD Applications, sync waves, app-of-apps profiles |

## Do NOT

- **Modify `base/` without updating all overlays** that depend on it
- **Hardcode version-specific values in base/** — channels/versions belong in overlays only
- **Delete existing overlays** — they may be in use by live clusters
- **Delete operator directories** without checking `grep -r <dir-name> gitops/cluster-config/apps/`
- **Commit a Subscription with `channel: patch-me-see-overlays-dir`** — that's the base placeholder
- **Apply two profiles simultaneously** — both create an Application named `cluster-config`, which conflicts
- **Break `kustomize build`** — always verify new overlays before committing

## Connection to Day 1

After provisioning clusters with `openshift-agent-install`, use this repo for Day 2:
```
openshift-agent-install  →  agent-gitops-quickstarts
  (provision cluster)         (configure + operate cluster)
  Day 1                        Day 2+
```
