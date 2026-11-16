
---

## Lessons Learned (from OCP 5.0 kvm-ocp-virt deployment, 2026-11-16)

### Add to `install-odf` skill — Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `diskmaker-discovery` DaemonSet shows DESIRED:0 | LocalVolumeDiscovery nodeSelector uses wrong node names (e.g. `ocp4-worker-*.example.com`) | Create a cluster-specific overlay patching node names to actual `kubernetes.io/hostname` values |
| `DiscoveryFailed: no discovery daemons scheduled` | Same as above | `oc get nodes -o jsonpath='{.items[*].metadata.labels.kubernetes\.io/hostname}'` to get real names |
| ODF StorageCluster stuck `OutOfSync/Missing` | kvm-ocp-virt profile missing `openshift-local-storage-instance` Application | Add the Application — without it `local-block` StorageClass is never created |
| `stable-5.0` channel not found | Operator hasn't published a 5.0-specific channel yet | Check real channels: `oc get packagemanifest <name> -o jsonpath='{.status.channels[*].name}'` |
| ArgoCD sync fails `console.openshift.io/v1alpha1 not found` | ConsolePlugin CRD not yet installed during dry-run | Add `SkipDryRunOnMissingResource=true` to syncOptions |
| StorageCluster uses wrong StorageClass | LocalVolumeSet base uses `lolvol` but StorageCluster expects `local-block` | kvm overlay must patch `storageClassName: local-block` |
| Sync wave moves before operator CRD is ready | selfHeal: false + no retry = stuck forever | Set `selfHeal: true` + retry with backoff on all apps |

### Add to `configure-lab` skill — New skill

Covers the full KVM lab post-install orchestration with --learn flag.

---

## Phase 6: New Scripts for agent-gitops-quickstarts

### `gitops/configure-redhat-labs.sh` — Multi-node lab/KVM orchestrator with self-learning

A wrapper script that:
1. Detects the cluster topology (SNO, 3-node, HA) and platform (KVM, bare metal, cloud)
2. Selects the right profile from `gitops/apps/`
3. Patches node-specific configs (node names, device paths) from live cluster data
4. Applies the profile via `oc apply`
5. With `--learn` flag: captures failures and appends them to the relevant skill's
   Common Failure Modes table automatically

```bash
# Usage:
./gitops/configure-redhat-labs.sh                    # auto-detect and apply
./gitops/configure-redhat-labs.sh --profile kvm-ocp-virt  # explicit profile
./gitops/configure-redhat-labs.sh --learn            # apply + capture lessons to skills
./gitops/configure-redhat-labs.sh --dry-run          # show what would be applied
```

Key `--learn` behaviors:
- On sync failure: `grep` ArgoCD application conditions → append to skill failure modes
- On node name mismatch: detect and auto-generate the correct kvm overlay patch
- On channel-not-found: query `packagemanifest` and update the overlay's channel value
- Commits updated SKILL.md files automatically with message:
  `fix: auto-learned <symptom> in <skill-name> failure modes [--learn]`

### `gitops/setup-gitea.sh` — Deploy self-hosted Gitea on OpenShift

Solves the core problem: ArgoCD needs a reachable git server. With GitHub:
- Node names, channel values, overlay patches must be pushed to GitHub first
- Air-gapped clusters can't reach GitHub at all

With Gitea on the cluster:
- ArgoCD pulls from `https://gitea-gitea.apps.<cluster>.<domain>`
- Changes take effect immediately without a GitHub push
- Works fully offline / air-gapped

```bash
# Usage:
./gitops/setup-gitea.sh                             # deploy Gitea + push this repo to it
./gitops/setup-gitea.sh --reconfigure-argocd        # update all ArgoCD repoURLs to Gitea
./gitops/setup-gitea.sh --sync-from-github          # pull latest from GitHub into Gitea
```

Workflow:
1. Deploy Gitea using existing `gitops/cluster-config/` kustomize (needs ODF storage first)
2. Push the agent-gitops-quickstarts repo to Gitea
3. Run `configure-repo.sh https://gitea-gitea.apps.<cluster>.<domain>/...` to update repoURLs
4. Push updated repoURLs to Gitea
5. ArgoCD now pulls from Gitea — changes are instant

Add these as new skills:
- `configure-lab` — triggers: "configure lab", "setup profile", "kvm lab setup"
- `setup-gitea` — triggers: "setup gitea", "self-hosted git", "air-gapped argocd", "offline gitops"

Both skills get the same self-learning Quick Diagnostics pattern: run real oc commands
first, detect mismatches, suggest or apply fixes, capture lessons on --learn.
