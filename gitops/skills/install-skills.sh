#!/usr/bin/env bash
# Install AI skills from gitops/skills/ into ~/.claude/skills/ (or the agent skills directory)
set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

SKILLS=(
  bootstrap-gitops
  install-odf
  install-virtualization
  install-acm
  configure-ztp
  install-aap
  deploy-profile
  troubleshoot-argocd
  configure-lab-environment
  create-kustomize-operator
  manage-argocd-apps
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Day 2 GitOps AI skills for agent-gitops-quickstarts.

Options:
  --all               Install all skills
  --list              List available skills
  --skill <name>      Install a single skill by name
  --install-dir <dir> Override install directory (default: ~/.claude/skills)
  -h, --help          Show this help

Available skills:
$(printf '  %s\n' "${SKILLS[@]}")
EOF
}

list_skills() {
  echo "Available skills (${#SKILLS[@]} total):"
  for skill in "${SKILLS[@]}"; do
    local skill_file="$SKILLS_DIR/$skill/SKILL.md"
    if [[ -f "$skill_file" ]]; then
      local desc
      desc=$(grep -m1 '^description:' "$skill_file" 2>/dev/null | sed 's/^description: *//' || echo "(no description)")
      printf '  %-30s %s\n' "$skill" "$desc"
    else
      printf '  %-30s (SKILL.md missing)\n' "$skill"
    fi
  done
}

install_skill() {
  local skill="$1"
  local src="$SKILLS_DIR/$skill"
  local dst="$INSTALL_DIR/$skill"

  if [[ ! -d "$src" ]]; then
    echo "ERROR: Skill '$skill' not found at $src" >&2
    exit 1
  fi

  mkdir -p "$dst"
  cp -r "$src/"* "$dst/"
  echo "Installed: $skill -> $dst"
}

INSTALL_ALL=false
LIST_ONLY=false
SINGLE_SKILL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) INSTALL_ALL=true ;;
    --list) LIST_ONLY=true ;;
    --skill) SINGLE_SKILL="$2"; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if $LIST_ONLY; then
  list_skills
  exit 0
fi

if [[ -n "$SINGLE_SKILL" ]]; then
  install_skill "$SINGLE_SKILL"
  exit 0
fi

if $INSTALL_ALL; then
  mkdir -p "$INSTALL_DIR"
  for skill in "${SKILLS[@]}"; do
    install_skill "$skill"
  done
  echo ""
  echo "All ${#SKILLS[@]} skills installed to $INSTALL_DIR"
  exit 0
fi

usage
exit 1
