# Documentation

| Guide | Description |
|---|---|
| [End-to-End Guide](end-to-end-guide.md) | Complete walkthrough: fresh cluster → fully configured environment |
| [Kustomize + ArgoCD Patterns](kustomize-argocd-patterns.md) | Base/overlay structure, sync waves, prune decisions, testing patterns |
| [gitops-catalog Integration](gitops-catalog.md) | How to use gitops-catalog as a reference when adding new operators |

## AI Skills Documentation

| Resource | Description |
|---|---|
| [`gitops/skills/README.md`](../gitops/skills/README.md) | Skills overview, all 11 skills, dependency chain, trigger phrases |
| [`gitops/skills/CONTRIBUTING_SKILLS.md`](../gitops/skills/CONTRIBUTING_SKILLS.md) | How to write a new skill |
| [`gitops/skills/create-kustomize-operator/SKILL.md`](../gitops/skills/create-kustomize-operator/SKILL.md) | Scaffold a new operator (base + overlays + ArgoCD App) |
| [`gitops/skills/manage-argocd-apps/SKILL.md`](../gitops/skills/manage-argocd-apps/SKILL.md) | Create and manage ArgoCD Applications and profiles |

## Other References

For the full AI-readable reference (operator catalog, OCP version matrix, bootstrap flow),
see [`llm.txt`](../llm.txt) in the repo root.
