# Execution Learnings

This directory stores auto-generated execution journals from `configure-redhat-labs.sh --learn`.

## What's in a journal file

Each `.yaml` file records one execution of `configure-redhat-labs.sh`:
- Environment type and platform (bare-metal, KVM, Equinix, Red Hat Labs, etc.)
- Node names, naming pattern, node count
- OCP version used, operator channels applied
- ODF and local-storage overlays used
- Profile deployed
- Whether the run succeeded or failed (and at which step)

## How the self-learning loop works

```
configure-redhat-labs.sh --learn
        │
        ▼
Writes <timestamp>-<env_type>.yaml here
        │
        ▼
learn-environment agent reads it
        │
        ├── SUCCESS → creates/updates overlays, profiles, wrapper scripts, skill Known Working Configs
        └── FAILURE → adds failure mode to relevant skill's Common Failure Modes table
```

## To trigger learning after a run

In Claude Code, say:

> "review the latest learning at gitops/learnings/ and update skills"

This invokes `.claude/agents/learn-environment.md`.

## File naming

```
<ISO-timestamp>-<env_type>.yaml
Examples:
  20261114T220000Z-red-hat-labs.yaml
  20261115T103045Z-bare-metal-or-kvm.yaml
  20261116T083012Z-aws.yaml
```

## Two-tier journal system (raw vs sanitized)

```
configure-redhat-labs.sh --learn
        │
        ├── writes <timestamp>-<env>.raw.yaml   ← NEVER COMMIT (gitignored)
        │          Full data: real node names, cluster domain, IPs
        │          Used locally by the learn-environment agent
        │
        └── writes <timestamp>-<env>.yaml       ← SAFE TO COMMIT
                   Sanitized: node names → node-N, domain → <redacted>
                   Useful patterns kept: platform, OCP version, node_count, outcome
```

### How sanitization works

```bash
# Manually sanitize a raw journal:
./gitops/sanitize-journal.sh gitops/learnings/my.raw.yaml gitops/learnings/my.yaml

# Check a file for remaining sensitive data:
./gitops/sanitize-journal.sh --check gitops/learnings/my.yaml

# Install the pre-commit hook that blocks sensitive data automatically:
./gitops/setup-git-hooks.sh
```

The pre-commit hook blocks:
- `*.raw.yaml` files (always)
- Any `.yaml` file that still contains FQDNs, IP addresses, or internal domain names

## Cloud platforms covered

The self-learning system captures patterns for:

| Platform | Key metadata captured | ODF overlay |
|---|---|---|
| AWS | `cloud_region`, `cloud_instance_type` (e.g., m5.4xlarge) | aws (gp2) |
| GCP | `cloud_region`, `cloud_instance_type` | gcp (standard-csi) |
| Azure | `cloud_region` | azure (managed-premium) |
| Bare-metal / KVM | `node_pattern` | bare-metal or kvm |
| Equinix Metal | `node_pattern` | equinix-cnv |
| Red Hat Labs | `node_pattern` = lab-worker- | equinix-cnv |

Cloud region codes (e.g., `us-east-1`, `europe-west1`) are **not sensitive** and
are retained in sanitized journals to help identify region-specific patterns.

## Privacy note

Raw `.raw.yaml` files are gitignored and stay on your local machine only.
If you're concerned about even sanitized data, add `*.yaml` to this directory's
`.gitignore` to keep all journals local. The learn-environment agent can still
read them locally without committing anything.
