#!/usr/bin/env bash
# Update all ArgoCD Application repoURL references to point to a different Git repository.
# Run this after forking the repo or setting up a self-hosted Git server (Gitea, GitLab, etc.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_ORIGIN="https://github.com/tosin2013/sno-quickstarts.git"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <new-repo-url>

Update all ArgoCD Application repoURL references in this repo to point to
a different Git remote (fork, Gitea instance, GitLab, Bitbucket, etc.)

Arguments:
  <new-repo-url>   Full HTTPS or SSH URL of your Git repository
                   Examples:
                     https://github.com/YOUR_ORG/sno-quickstarts.git
                     https://gitea.apps.cluster.example.com/admin/sno-quickstarts.git
                     git@github.com:YOUR_ORG/sno-quickstarts.git

Options:
  --dry-run        Show what would change without making any edits
  --origin <url>   Current repo URL to replace (default: $DEFAULT_ORIGIN)
  -h, --help       Show this help

Examples:
  # Fork to your GitHub org:
  $(basename "$0") https://github.com/my-org/sno-quickstarts.git

  # Point to a Gitea instance on OpenShift:
  $(basename "$0") https://gitea.apps.mycluster.example.com/admin/sno-quickstarts.git

  # Point to GitLab self-hosted:
  $(basename "$0") https://gitlab.company.com/team/sno-quickstarts.git
EOF
}

DRY_RUN=false
ORIGIN="$DEFAULT_ORIGIN"
NEW_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --origin) ORIGIN="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) NEW_URL="$1" ;;
  esac
  shift
done

if [[ -z "$NEW_URL" ]]; then
  echo "ERROR: No new repo URL provided." >&2
  echo ""
  usage
  exit 1
fi

echo "Repository reconfiguration"
echo "  From: $ORIGIN"
echo "  To:   $NEW_URL"
echo ""

# Find all YAML files in gitops/ that reference the origin URL
CHANGED=0
while IFS= read -r -d '' file; do
  if grep -qF "$ORIGIN" "$file" 2>/dev/null; then
    if $DRY_RUN; then
      echo "[dry-run] Would update: ${file#$REPO_ROOT/}"
    else
      # Handle both single-space and double-space repoURL variants
      sed -i "s|$ORIGIN|$NEW_URL|g" "$file"
      echo "Updated: ${file#$REPO_ROOT/}"
    fi
    ((CHANGED++)) || true
  fi
done < <(find "$REPO_ROOT/gitops" \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

echo ""
if $DRY_RUN; then
  echo "$CHANGED file(s) would be updated."
else
  echo "$CHANGED file(s) updated."
  echo ""
  echo "Next steps:"
  echo "  1. Push this updated repo to: $NEW_URL"
  echo "  2. Ensure ArgoCD can reach $NEW_URL"
  echo "     - For private repos: create a secret in openshift-gitops namespace"
  echo "     - oc create secret generic repo-creds -n openshift-gitops \\"
  echo "         --from-literal=username=<user> \\"
  echo "         --from-literal=password=<token-or-password> \\"
  echo "         --from-literal=url=$NEW_URL"
  echo "     - oc label secret repo-creds -n openshift-gitops argocd.argoproj.io/secret-type=repository"
  echo "  3. Bootstrap ArgoCD: ./deploy.sh"
  echo "  4. Apply a profile: oc apply -f gitops/apps/<profile>/cluster-config.yaml"
fi
