#!/usr/bin/env bash
# Deploy a self-hosted Gitea instance on OpenShift, then push this repo into it.
# Gitea lets air-gapped or on-prem clusters host their own Git server without GitHub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GITEA_DEPLOY_SCRIPT_URL="https://raw.githubusercontent.com/tosin2013/openshift-demos/master/quick-scripts/deploy-gitea.sh"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea_admin}"
GITEA_REPO_NAME="${GITEA_REPO_NAME:-sno-quickstarts}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy Gitea on OpenShift and push this repo into it.
Then reconfigure all ArgoCD Application repoURL references to point at Gitea.

Environment variables:
  GITEA_ADMIN_USER   Gitea admin username (default: gitea_admin)
  GITEA_REPO_NAME    Gitea repo name (default: sno-quickstarts)

Options:
  --deploy-only      Only deploy Gitea, skip repo push and URL reconfiguration
  --push-only        Skip Gitea deployment, only push and reconfigure (Gitea already running)
  --dry-run          Show what would change without making changes
  -h, --help         Show this help

Steps this script performs:
  1. Download and run deploy-gitea.sh (deploys Gitea on current OpenShift cluster)
  2. Wait for Gitea to be accessible
  3. Create a repo in Gitea via its API
  4. Add Gitea as a git remote and push
  5. Run configure-repo.sh to update all ArgoCD Application repoURL references
  6. Print next steps for creating ArgoCD repo credentials

Requirements:
  - Logged in to OpenShift: oc whoami
  - git installed
  - curl installed
EOF
}

DEPLOY_GITEA=true
PUSH_REPO=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-only) PUSH_REPO=false ;;
    --push-only) DEPLOY_GITEA=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# Verify cluster access
if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged in to an OpenShift cluster. Run 'oc login' first." >&2
  exit 1
fi

CLUSTER_DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
if [[ -z "$CLUSTER_DOMAIN" ]]; then
  echo "ERROR: Could not determine cluster ingress domain." >&2
  exit 1
fi

GITEA_ROUTE="https://gitea-gitea.${CLUSTER_DOMAIN}"
GITEA_REPO_URL="${GITEA_ROUTE}/${GITEA_ADMIN_USER}/${GITEA_REPO_NAME}.git"

echo "Cluster domain:  $CLUSTER_DOMAIN"
echo "Gitea URL:       $GITEA_ROUTE"
echo "Repo URL:        $GITEA_REPO_URL"
echo ""

if $DRY_RUN; then
  echo "[dry-run] Would perform the following:"
  $DEPLOY_GITEA && echo "  1. Deploy Gitea via deploy-gitea.sh"
  $PUSH_REPO    && echo "  2. Push this repo to $GITEA_REPO_URL"
  $PUSH_REPO    && echo "  3. Run: ./configure-repo.sh $GITEA_REPO_URL"
  exit 0
fi

# Step 1: Deploy Gitea
if $DEPLOY_GITEA; then
  echo "==> Deploying Gitea on OpenShift..."
  TMPDIR=$(mktemp -d)
  trap "rm -rf $TMPDIR" EXIT
  curl -fsSL "$GITEA_DEPLOY_SCRIPT_URL" -o "$TMPDIR/deploy-gitea.sh"
  chmod +x "$TMPDIR/deploy-gitea.sh"
  bash "$TMPDIR/deploy-gitea.sh"

  echo ""
  echo "Waiting for Gitea to be accessible at $GITEA_ROUTE ..."
  for i in $(seq 1 30); do
    if curl -sf "$GITEA_ROUTE" -o /dev/null 2>/dev/null; then
      echo "Gitea is up!"
      break
    fi
    echo "  Attempt $i/30 — waiting 10s..."
    sleep 10
  done
fi

# Step 2: Push this repo to Gitea
if $PUSH_REPO; then
  echo ""
  echo "==> Setting up repo in Gitea..."

  # Prompt for admin password
  echo "Enter Gitea admin password for user '$GITEA_ADMIN_USER':"
  read -rs GITEA_PASSWORD
  echo ""

  # Create repo via Gitea API
  echo "Creating repository '$GITEA_REPO_NAME' in Gitea..."
  HTTP_STATUS=$(curl -sf -w "%{http_code}" -o /dev/null \
    -X POST "${GITEA_ROUTE}/api/v1/user/repos" \
    -u "${GITEA_ADMIN_USER}:${GITEA_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${GITEA_REPO_NAME}\",\"private\":false,\"auto_init\":false}" 2>/dev/null || echo "000")

  if [[ "$HTTP_STATUS" == "201" ]]; then
    echo "Repository created."
  elif [[ "$HTTP_STATUS" == "409" ]]; then
    echo "Repository already exists — continuing."
  else
    echo "WARNING: Unexpected status $HTTP_STATUS when creating repo. Continuing anyway..."
  fi

  # Add Gitea remote and push
  AUTH_REPO_URL="${GITEA_ROUTE/https:\/\//https:\/\/${GITEA_ADMIN_USER}:${GITEA_PASSWORD}@}/${GITEA_ADMIN_USER}/${GITEA_REPO_NAME}.git"

  echo "Pushing to Gitea..."
  cd "$REPO_ROOT"
  git remote remove gitea 2>/dev/null || true
  git remote add gitea "$AUTH_REPO_URL"
  git push gitea "$(git rev-parse --abbrev-ref HEAD):main" --force
  git remote remove gitea

  echo ""
  echo "==> Reconfiguring all ArgoCD Application repoURL references..."
  bash "$SCRIPT_DIR/configure-repo.sh" "$GITEA_REPO_URL"
fi

echo ""
echo "====================================================="
echo "Gitea setup complete!"
echo "====================================================="
echo ""
echo "Gitea UI:   $GITEA_ROUTE"
echo "Repo URL:   $GITEA_REPO_URL"
echo ""
echo "ArgoCD repo credentials (run after bootstrapping ArgoCD):"
echo ""
echo "  oc create secret generic gitea-repo-creds -n openshift-gitops \\"
echo "    --from-literal=username=${GITEA_ADMIN_USER} \\"
echo "    --from-literal=password=<your-gitea-password-or-token> \\"
echo "    --from-literal=url=${GITEA_REPO_URL}"
echo ""
echo "  oc label secret gitea-repo-creds -n openshift-gitops \\"
echo "    argocd.argoproj.io/secret-type=repository"
echo ""
echo "Then bootstrap ArgoCD: ./deploy.sh"
