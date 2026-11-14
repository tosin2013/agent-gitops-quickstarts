# Contributing Skills

This guide explains how to add a new AI skill to agent-gitops-quickstarts.

## What is a Skill?

A skill is a directory containing a `SKILL.md` file that tells an AI agent how to perform
a specific Day 2 GitOps operation on an OpenShift cluster. Skills follow the agentskills.io
specification and are designed to be loaded by AI coding assistants (Claude Code, etc.).

## Skill Directory Structure

```
gitops/skills/<skill-name>/
  SKILL.md          # Required: skill definition (see template below)
  scripts/          # Optional: helper scripts symlinked or adapted from gitops/
    deploy.sh -> ../../../../gitops/deploy.sh
    wait-for-sync.sh
```

## SKILL.md Template

```markdown
---
name: <skill-name>
description: <one-line description of what this skill does>
version: "1.0"
compatibility:
  ocp: ">=4.14"
  tools: ["oc", "kustomize"]
triggers:
  - "<phrase that invokes this skill>"
  - "<another trigger phrase>"
---

# <Skill Name>

## Overview

<2-3 sentence description of what this skill does and when to use it.>

## Prerequisites

- OpenShift cluster running OCP <version range>
- `oc` CLI authenticated: `oc whoami` returns a valid user
- <any other prerequisites>

## Quick Diagnostics

Run these before starting to understand current state:

```bash
# Check cluster access
oc whoami
oc cluster-info

# Check relevant resources
oc get <resource> -n <namespace>
```

## Steps

### Step 1: <Action>

<Description of what this step does and why.>

```bash
<command>
```

Expected output: `<what success looks like>`

### Step 2: <Action>

...

## Verification

After completing all steps, verify success:

```bash
oc get <resource> -n <namespace>
# Expected: STATUS=Ready/Succeeded/Running
```

## Common Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| `<error message>` | `<why it happens>` | `<how to fix it>` |

## Related Skills

- [[bootstrap-gitops]] — Must run before this skill
- [[<next-skill>]] — Run after this skill completes
```

## Rules for New Skills

1. **name** must be lowercase-hyphenated and match the directory name exactly
2. **Quick Diagnostics** must use real `oc` commands that work on a live cluster
3. **Common Failure Modes** must have at least one entry with a real failure you've seen
4. **Related Skills** must link the full dependency chain (what comes before and after)
5. **triggers** must include the most natural English phrase someone would say to invoke this skill

## Skill Self-Improvement (Required Reading)

Per AGENTS.md: when you execute a skill and encounter a failure not in Common Failure Modes,
you **must** add it to the skill's SKILL.md. This keeps skills accurate as the ecosystem evolves.

## Testing a New Skill

1. Create the skill directory and SKILL.md
2. Verify the skill installs: `./gitops/skills/install-skills.sh --skill <name>`
3. Walk through the steps on a real or simulated cluster
4. Confirm the Quick Diagnostics commands work
5. Add at least one real failure mode from your testing
6. Submit a PR with the new skill

## Naming Conventions

| Pattern | Example |
|---|---|
| Install an operator | `install-<operator-name>` |
| Configure a feature | `configure-<feature>` |
| Deploy a profile | `deploy-<profile-type>` |
| Troubleshoot a system | `troubleshoot-<system>` |
| Bootstrap infrastructure | `bootstrap-<infra>` |
