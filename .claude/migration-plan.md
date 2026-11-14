# Migration Plan: sno-quickstarts → agent-gitops-quickstarts

This file tells Claude what work is needed when you open this repo.
See the full context in tosin2013/openshift-agent-install's session history.

## Goal

Refactor this repo into a broader, AI-augmented GitOps quickstarts library.
The name `sno-quickstarts` undersells it — it already covers HA, Equinix, VMware,
ACM hubs, and 3-node ZTP, not just SNO. Add the same AI skills harness as
`openshift-agent-install` to create a coherent Day 1 → Day 2 pipeline.

## Two-Repo Pipeline

```
openshift-agent-install  →  agent-gitops-quickstarts
  (provision cluster)         (configure + operate cluster)
  Day 1                        Day 2+
```

## Work to Do (in priority order)

### Phase 1: Foundation
1. Add Apache 2.0 LICENSE file
2. Add GitHub topics: openshift, gitops, argocd, odf, rhacm, kustomize, openshift-5
3. Create `llm.txt` — comprehensive reference:
   - GitOps bootstrap procedure (gitops/deploy.sh → ArgoCD → app-of-apps)
   - All 26 operator categories with descriptions and OCP version matrix
   - Profile catalog (every directory under gitops/apps/ explained)
   - OCP 4.x vs 5.0 compatibility notes
   - Troubleshooting ArgoCD sync failures
4. Create `AGENTS.md` with universal guardrails including **Skill Self-Improvement**:
   - When a failure is found not in Common Failure Modes → add it and commit
   - When step order is wrong → fix and explain why
   - Preserve all Kustomize base/overlay patterns
   - Don't delete existing overlays

### Phase 2: AI Skills Harness
Create `gitops/skills/` with 8 SKILL.md files following agentskills.io spec.
Model exactly after tosin2013/openshift-agent-install/hack/skills/deploy-cluster-kvm/SKILL.md.

Standards:
- `name:` must be lowercase-hyphenated matching directory name
- `compatibility:` document OCP versions and oc CLI requirement
- Quick Diagnostics section MUST run real `oc` commands to check live state
- `scripts/` subdirectory with symlinks to gitops/*.sh and oc wrappers
- Related Skills section linking the dependency chain

Skills (priority order):
1. `bootstrap-gitops` — gitops/deploy.sh; triggers: "bootstrap gitops", "install argocd"
2. `install-odf` — ODF operator + StorageCluster; triggers: "install ODF", "storage"
3. `install-virtualization` — CNV; triggers: "OpenShift Virtualization", "CNV", "KubeVirt"
4. `install-acm` — RHACM hub; triggers: "install RHACM", "hub cluster", "ACM"
5. `configure-ztp` — ZTP spokes; triggers: "ZTP", "spoke cluster"
6. `install-aap` — AAP operator; triggers: "Ansible Automation Platform", "AAP"
7. `deploy-profile` — full cluster profile; triggers: "deploy profile", "configure cluster"
8. `troubleshoot-argocd` — sync failures; triggers: "ArgoCD not syncing", "sync failed"

Also create `gitops/skills/pull-rh-skills.sh` — adapted from:
https://raw.githubusercontent.com/tosin2013/openshift-agent-install/refs/heads/main/hack/skills/pull-rh-skills.sh

Focus on Day-2 relevant Red Hat skills:
- openshift/agentic-skills: cluster-troubleshoot, cluster-update, gitops
- RHEcosystemAppEng/agentic-plugins: ocp-admin/*
- redhat-developer/agentic-skills: all 4 Argo CD skills

Also create `gitops/skills/CONTRIBUTING_SKILLS.md` — how to add new skills.

### Phase 3: OCP 5.0 Overlays
Add stable-5.0 channel overlays for top 5 operators (research correct channel names first):
- gitops/cluster-config/openshift-data-foundation-operator/overlays/stable-5.0/
- gitops/cluster-config/openshift-virtualization/overlays/stable-5.0/
- gitops/cluster-config/rhacm-operator/overlays/stable-5.0/
- gitops/cluster-config/openshift-pipelines-operator/overlays/latest-5.0/
- gitops/cluster-config/openshift-local-storage/overlays/stable-5.0/

ODF 5.0 note: uses RHCOS 10 nodes (x86-64-v3+ required).

### Phase 4: CLAUDE.md
Model after tosin2013/openshift-agent-install/CLAUDE.md. Include:
- Project overview: Day 2 GitOps config via ArgoCD + Kustomize
- Repository structure (gitops/apps/, gitops/cluster-config/, gitops/skills/)
- Kustomize base/overlay pattern explanation
- Profile catalog: when to use which app in gitops/apps/
- How to add a new operator (copy existing, create overlays)
- How to add a new OCP version overlay
- Skills Reference (auto-generated section)
- Do NOT: modify base/ without updating all overlays; delete operator dirs

### Phase 5: Optional Deployment Agent
Create `.claude/agents/gitops-operator.md`:
- Chains skills: bootstrap-gitops → install-odf → install-virtualization
- Runs `oc get application -n openshift-gitops` before each step
- Waits for ArgoCD sync before proceeding to next operator
- OCP 5.0 aware: knows about RHCOS 10 ODF disk requirements

## Verification
- `gitops/skills/install-skills.sh --list` shows 8 skills
- CLAUDE.md Skills Reference has all 8 skills
- llm.txt covers all 26 operator categories
- Each skill's Quick Diagnostics runs real oc commands
- OCP 5.0 overlays pass `kustomize build`

## Connection Back to openshift-agent-install
After completing this work, also update openshift-agent-install:
- Add to deploy-cluster-kvm and deploy-cluster-baremetal skills' Related Skills:
  "After deployment: use agent-gitops-quickstarts for Day 2 operator configuration"
