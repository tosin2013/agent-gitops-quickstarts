# AGENTS.md — Universal AI Agent Guardrails

This file defines rules that all AI agents must follow when working in this repository.
These rules apply regardless of the agent framework, model, or task.

## Project Context

This is an ArgoCD + Kustomize GitOps repository for Day 2 OpenShift configuration.
The fundamental unit of work is a Kustomize overlay — a directory that patches a base.
Every operator has a `base/` (with placeholder values) and one or more `overlays/<channel>/`.

Read `llm.txt` for the complete reference on repo structure, operator catalog, and profiles.

## Mandatory Rules

### 1. Never break `kustomize build`

Before committing any change that touches a Kustomize resource, verify:

```bash
kustomize build <changed-overlay-path>
```

If it fails, fix it before committing. Never push manifests that fail to build.

### 2. Preserve base/overlay separation

- **Never hardcode version-specific values in base/**. The base must remain version-agnostic.
  Channels, versions, and platform-specific values belong in overlays.
- **Never modify base/ without updating all overlays that depend on it**.
  If you add a field to base, ensure every overlay's patch file still applies cleanly.

### 3. Never delete existing overlays

Existing overlays may be in use by live clusters or referenced in ArgoCD Applications.
Deleting an overlay breaks those deployments silently (ArgoCD will show sync errors).
If an overlay is obsolete, add a deprecation notice to its README.md instead.

### 4. Never delete operator directories

Operator directories under `gitops/cluster-config/` represent deployment knowledge.
If you think a directory is unused, check all files in `gitops/cluster-config/apps/`
before removing it. Use `grep -r <operator-dir-name> gitops/cluster-config/apps/`.

### 5. Channel name accuracy

When adding a new OCP version overlay, verify the channel name from the official
Red Hat documentation before writing it. Do not guess.

Check: https://docs.redhat.com — use the Red Hat Docs MCP server if available.
Common patterns:
- ODF: `stable-<ocp-version>` (e.g. `stable-4.19`, `stable-5.0`)
- Local Storage: `stable-<ocp-version>` (e.g. `stable-4.19`, `stable-5.0`)
- ODF-LVM: `stable-<ocp-version>` (e.g. `stable-4.19`)
- ACM: `release-<acm-version>` (e.g. `release-2.11`) or `stable-5.0` for ACM 5.0
- CNV: `stable` (not OCP-version-specific)
- Pipelines: `latest` or `pipelines-<version>`

### 6. Platform storage class selection

When creating a new ODF StorageCluster overlay, use the correct storage class for the platform:

| Platform | Storage Class | Notes |
|---|---|---|
| AWS | `gp2` or `gp3` | EBS volumes; use `gp3` for newer clusters |
| GCP | `standard-csi` or `pd-ssd` | Persistent Disk |
| Azure | `managed-premium` | Premium SSD |
| VMware vSphere | `thin` or vSphere datastore class | Check `oc get storageclass` |
| Bare-metal / KVM / Equinix | `local-block` or LocalVolumeSet class | Requires local-storage operator |

### 7. ArgoCD Application paths must match actual overlay paths

When adding a new overlay, also check whether any ArgoCD Application in
`gitops/cluster-config/apps/` references the old path and needs updating.
Run: `grep -r <operator-name> gitops/cluster-config/apps/`

---

## Skill Self-Improvement Rule

This rule applies to all skills in `gitops/skills/`:

> When you execute a skill and encounter a failure that is **not listed** in the skill's
> **Common Failure Modes** section, you must:
> 1. Add the new failure mode to the skill's SKILL.md `Common Failure Modes` section
> 2. Include: the symptom, the root cause, and the fix
> 3. Commit the update with a message like:
>    `docs(skills/<name>): add failure mode — <brief description>`

Similarly, if the skill's step ordering causes a problem:
1. Fix the step order in SKILL.md
2. Explain why in the commit message (e.g., "operator must be Running before creating instance")

Skills are living documents. Keep them accurate.

### Automated Self-Learning (configure-lab-environment)

The **learn-environment** agent (`.claude/agents/learn-environment.md`) implements this rule
automatically for `configure-redhat-labs.sh` runs. The feedback loop is:

```
configure-redhat-labs.sh --learn
        → writes gitops/learnings/<timestamp>.yaml
        → "review the latest learning at gitops/learnings/ and update skills"
        → learn-environment agent reads journal, creates/updates:
            • overlays for new node naming patterns
            • profiles for new environment types
            • wrapper scripts for common environments
            • failure modes in configure-lab-environment/SKILL.md
            • Known Working Configurations table
```

This means every new cluster type that gets configured successfully makes the repo smarter
for the next person running on a similar cluster.

---

## Step Order for Adding a New Operator

1. Copy an existing, similar operator directory as a starting point
2. Update the `base/` Subscription: set `channel: patch-me-see-overlays-dir`
3. Create at least one overlay for the current stable OCP version
4. Verify: `kustomize build <new-overlay-path>`
5. Add the operator to `llm.txt` under the appropriate category
6. Optionally add it to a profile in `gitops/cluster-config/apps/<profile>/`

## Step Order for Adding a New OCP Version Overlay

1. Look up the channel name in Red Hat documentation
2. Create `<operator>/operator/overlays/<channel-name>/`
3. Create `kustomization.yaml` (copy from an adjacent overlay, change nothing except the patch reference)
4. Create `patch-channel.yaml` with the correct channel name
5. Verify: `kustomize build <new-overlay-path>`
6. Update `llm.txt` OCP Version Matrix table

## Verification Checklist Before Committing

- [ ] `kustomize build` passes for all modified/added overlays
- [ ] No `grep -r patch-me-see-overlays-dir` hits in committed overlays
- [ ] ArgoCD Application paths in `gitops/cluster-config/apps/` are consistent
- [ ] `llm.txt` reflects any new operators, channels, or profiles added
- [ ] If a skill was modified: failure modes and step order are still accurate
