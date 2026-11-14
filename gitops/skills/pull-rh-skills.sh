#!/usr/bin/env bash
# Pull Day 2 relevant Red Hat agentic skills from upstream repos
set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${1:-$SKILLS_DIR/rh-upstream}"

echo "Pulling Red Hat agentic skills to: $DEST_DIR"
mkdir -p "$DEST_DIR"

# Helper: clone or update a repo
clone_or_update() {
  local url="$1"
  local dest="$2"
  if [[ -d "$dest/.git" ]]; then
    echo "  Updating $dest"
    git -C "$dest" pull --ff-only
  else
    echo "  Cloning $url"
    git clone --depth=1 "$url" "$dest"
  fi
}

# Helper: copy skills from a cloned repo
copy_skills() {
  local src="$1"
  local pattern="$2"
  local label="$3"
  echo ""
  echo "==> $label"
  find "$src" -type d -name "SKILL.md" -prune -o \
    -name "SKILL.md" -print 2>/dev/null | while read -r f; do
    local skill_dir
    skill_dir="$(dirname "$f")"
    local skill_name
    skill_name="$(basename "$skill_dir")"
    if echo "$skill_dir" | grep -qE "$pattern"; then
      echo "  Copying skill: $skill_name"
      cp -r "$skill_dir" "$DEST_DIR/$skill_name"
    fi
  done
}

# 1. openshift/agentic-skills — cluster-troubleshoot, cluster-update, gitops
REPO1="$DEST_DIR/.src/openshift-agentic-skills"
clone_or_update "https://github.com/openshift/agentic-skills.git" "$REPO1" || \
  echo "  WARN: Could not clone openshift/agentic-skills (may require auth)"
if [[ -d "$REPO1" ]]; then
  copy_skills "$REPO1" "cluster-troubleshoot|cluster-update|gitops" \
    "openshift/agentic-skills (cluster-troubleshoot, cluster-update, gitops)"
fi

# 2. RHEcosystemAppEng/agentic-plugins — ocp-admin/*
REPO2="$DEST_DIR/.src/agentic-plugins"
clone_or_update "https://github.com/RHEcosystemAppEng/agentic-plugins.git" "$REPO2" || \
  echo "  WARN: Could not clone RHEcosystemAppEng/agentic-plugins"
if [[ -d "$REPO2" ]]; then
  copy_skills "$REPO2" "ocp-admin" \
    "RHEcosystemAppEng/agentic-plugins (ocp-admin/*)"
fi

# 3. redhat-developer/agentic-skills — all Argo CD skills
REPO3="$DEST_DIR/.src/redhat-developer-agentic-skills"
clone_or_update "https://github.com/redhat-developer/agentic-skills.git" "$REPO3" || \
  echo "  WARN: Could not clone redhat-developer/agentic-skills"
if [[ -d "$REPO3" ]]; then
  copy_skills "$REPO3" "argo|argocd|gitops" \
    "redhat-developer/agentic-skills (Argo CD skills)"
fi

echo ""
echo "Done. Upstream skills saved to: $DEST_DIR"
echo "Review them and copy relevant ones into gitops/skills/ as needed."
