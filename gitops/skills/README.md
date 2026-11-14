# AI Skills — agent-gitops-quickstarts

This directory contains AI skill definitions for Day 2 OpenShift configuration.
Skills are structured instruction files that tell an AI agent (Claude Code, etc.)
how to perform a specific GitOps operation on a live cluster, step by step.

## Available Skills (9 total)

```bash
./install-skills.sh --list
```

| Skill | Triggers | What it does |
|---|---|---|
| [`bootstrap-gitops`](bootstrap-gitops/SKILL.md) | "bootstrap gitops", "install argocd" | Installs OpenShift GitOps (ArgoCD) on a fresh cluster |
| [`install-odf`](install-odf/SKILL.md) | "install ODF", "install storage" | Installs OpenShift Data Foundation (Ceph) + StorageCluster |
| [`install-virtualization`](install-virtualization/SKILL.md) | "OpenShift Virtualization", "CNV" | Installs CNV/KubeVirt + HyperConverged instance |
| [`install-acm`](install-acm/SKILL.md) | "install RHACM", "hub cluster" | Installs RHACM hub + MultiClusterHub |
| [`configure-ztp`](configure-ztp/SKILL.md) | "ZTP", "spoke cluster" | Configures ZTP spoke provisioning via RHACM |
| [`install-aap`](install-aap/SKILL.md) | "Ansible Automation Platform", "AAP" | Installs AAP operator + Controller + Hub |
| [`deploy-profile`](deploy-profile/SKILL.md) | "deploy profile", "configure cluster" | Deploys a full ArgoCD cluster profile |
| [`troubleshoot-argocd`](troubleshoot-argocd/SKILL.md) | "ArgoCD not syncing", "sync failed" | Diagnoses and fixes ArgoCD sync failures |
| [`configure-lab-environment`](configure-lab-environment/SKILL.md) | "configure lab", "KVM cluster setup" | Full multi-node setup: infra nodes + LSO + ODF + profile |

## Quick Start

### Install skills into Claude Code

```bash
# Install all skills:
./install-skills.sh --all

# Install one skill:
./install-skills.sh --skill bootstrap-gitops

# List with descriptions:
./install-skills.sh --list
```

### Use a skill in Claude Code

Once installed, trigger a skill by typing a natural language phrase:

```
"bootstrap gitops on my cluster"
"install ODF on OCP 4.22"
"configure lab environment with nodes worker-0,worker-1,worker-2"
"deploy the kvm-ocp-virt profile"
```

The agent reads the SKILL.md, runs the diagnostic commands, and walks through the steps.

### Pull community skills from Red Hat

```bash
./pull-rh-skills.sh
```

This pulls Day-2 relevant agentic skills from:
- `openshift/agentic-skills` — cluster-troubleshoot, cluster-update, gitops
- `RHEcosystemAppEng/agentic-plugins` — ocp-admin/*
- `redhat-developer/agentic-skills` — Argo CD skills

## Skill Execution Order (Dependency Chain)

Skills have dependencies. Run them in this order:

```
1. bootstrap-gitops          ← always first; installs ArgoCD
        │
        ├── 2a. install-odf              ← storage (needed by VMs, apps)
        │          │
        │          └── 2b. install-virtualization   ← VMs on top of ODF
        │
        ├── 2c. install-acm              ← hub cluster management
        │          │
        │          └── 3. configure-ztp ← ZTP spokes (needs RHACM hub)
        │
        └── 2d. deploy-profile           ← full app-of-apps profile
                   │
                   └── troubleshoot-argocd  ← use if any app fails to sync
```

**For multi-node lab/KVM (single command):**
```bash
./configure-redhat-labs.sh --configure-infra-nodes --configure-storage \
  --profile kvm-ocp-virt --learn
```

This runs `bootstrap-gitops` → `configure-lab-environment` → `deploy-profile` automatically.

## Self-Improvement Rule

Skills are **living documents**. When you encounter a failure not in a skill's
Common Failure Modes table:

1. Add it to the skill's `SKILL.md`
2. Commit: `docs(skills/<name>): add failure mode — <description>`

After running `configure-redhat-labs.sh --learn`, the **learn-environment** agent
does this automatically for the `configure-lab-environment` skill.

## Skill File Structure

```
<skill-name>/
  SKILL.md          # Skill definition (frontmatter + steps + failure modes)
  scripts/          # Optional helper scripts
```

Each `SKILL.md` has:
- **Frontmatter** — name, compatibility, triggers
- **Quick Diagnostics** — real `oc` commands to run first
- **Steps** — numbered, with commands and expected output
- **Common Failure Modes** — symptom → root cause → fix table
- **Related Skills** — dependency links

## Contributing

See [`CONTRIBUTING_SKILLS.md`](CONTRIBUTING_SKILLS.md) for how to add a new skill.
