#!/usr/bin/env bash
# Install git pre-commit hook that blocks sensitive data from being committed.
# Run once after cloning: ./gitops/setup-git-hooks.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK_FILE="$HOOKS_DIR/pre-commit"
SANITIZER="$REPO_ROOT/gitops/sanitize-journal.sh"

cat > "$HOOK_FILE" << 'HOOK'
#!/usr/bin/env bash
# Pre-commit hook: block sensitive data in gitops/learnings/ journals.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SANITIZER="$REPO_ROOT/gitops/sanitize-journal.sh"
FAILED=0

# Check all staged journal YAML files in gitops/learnings/
while IFS= read -r file; do
  [[ "$file" == gitops/learnings/*.yaml ]] || continue
  [[ "$file" == *.raw.yaml ]] && { echo "BLOCKED: raw journal '$file' staged for commit. Only sanitized journals (.yaml not .raw.yaml) may be committed."; FAILED=1; continue; }

  if [[ -f "$REPO_ROOT/$file" ]] && [[ -x "$SANITIZER" ]]; then
    if ! bash "$SANITIZER" --check "$REPO_ROOT/$file" > /dev/null 2>&1; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "BLOCKED: Sensitive data detected in $file"
      echo ""
      bash "$SANITIZER" --check "$REPO_ROOT/$file" 2>&1 | head -10
      echo ""
      echo "Fix: run the sanitizer first:"
      echo "  ./gitops/sanitize-journal.sh $file $file"
      echo "  git add $file"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      FAILED=1
    fi
  fi
done < <(git diff --cached --name-only)

# Also block common sensitive file patterns anywhere in the repo
while IFS= read -r file; do
  case "$file" in
    *.env|*.pem|*.key|*kubeconfig*|*pull-secret*|*credentials*)
      echo "BLOCKED: Likely sensitive file staged: $file"
      FAILED=1
      ;;
  esac
done < <(git diff --cached --name-only)

[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
HOOK

chmod +x "$HOOK_FILE"
echo "Pre-commit hook installed: $HOOK_FILE"
echo ""
echo "The hook will:"
echo "  • Block .raw.yaml files from gitops/learnings/ (keep sensitive data local)"
echo "  • Block unsanitized .yaml journals that still contain FQDNs/IPs/internal names"
echo "  • Block common sensitive file types (.env, .pem, .key, kubeconfig, pull-secret)"
echo ""
echo "To sanitize a journal before committing:"
echo "  ./gitops/sanitize-journal.sh gitops/learnings/<file>.raw.yaml gitops/learnings/<file>.yaml"
