#!/usr/bin/env bash
# Scrub sensitive data from a learning journal before committing to git.
#
# What gets redacted:
#   cluster_domain  — full FQDN of the cluster ingress domain
#   node_names      — actual hostnames replaced with positional node-N aliases
#   failure_detail  — FQDNs/IPs/internal names within error messages
#
# What is preserved (safe, useful for learning):
#   env_type, platform, ocp_version, node_count, node_pattern, outcome,
#   steps_completed, overlay names, profile names
#
# Usage:
#   ./sanitize-journal.sh <input.yaml>              # prints sanitized YAML to stdout
#   ./sanitize-journal.sh <input.yaml> <output.yaml> # writes to file
#   ./sanitize-journal.sh --check <file.yaml>       # exit 0 if clean, 1 if sensitive data found
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check] <input.yaml> [<output.yaml>]

Scrub sensitive data from a learning journal file.

Options:
  --check    Check mode: exit 1 if sensitive data found, 0 if clean (no output written)
  -h, --help Show this help
EOF
}

CHECK_MODE=false
INPUT=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_MODE=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$INPUT" ]]; then
        INPUT="$1"
      elif [[ -z "$OUTPUT" ]]; then
        OUTPUT="$1"
      else
        echo "Too many arguments" >&2; usage; exit 1
      fi
      ;;
  esac
  shift
done

[[ -z "$INPUT" ]] && { echo "ERROR: No input file specified" >&2; usage; exit 1; }
[[ -f "$INPUT" ]] || { echo "ERROR: File not found: $INPUT" >&2; exit 1; }

# ── Sensitive pattern detection ───────────────────────────────────────────────
# Patterns that indicate the data has real hostnames/domains/IPs
SENSITIVE_PATTERNS=(
  # FQDN with 2+ dots that isn't a placeholder
  '\.[a-z0-9-]+\.[a-z]{2,}[:/"]'
  # AWS-style node names with IPs (ip-10-x-x-x)
  'ip-[0-9]+-[0-9]+'
  # Kubernetes-style internal FQDNs
  '\.(svc|cluster)\.local'
  # Cloud internal names
  'compute\.internal'
  'ec2\.internal'
  '.+\.example\.'   # sample domains that weren't replaced
)

check_for_sensitive() {
  local found=false
  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    if grep -qE "$pattern" "$INPUT" 2>/dev/null; then
      echo "SENSITIVE: pattern '$pattern' found in $INPUT" >&2
      found=true
    fi
  done
  $found && return 1 || return 0
}

if $CHECK_MODE; then
  if check_for_sensitive; then
    echo "OK: No sensitive patterns detected in $INPUT"
    exit 0
  else
    exit 1
  fi
fi

# ── Sanitization ──────────────────────────────────────────────────────────────
sanitize() {
  local content
  content=$(cat "$INPUT")

  # 1. Redact cluster_domain — replace FQDN with <cluster-domain-redacted>
  content=$(echo "$content" | sed -E \
    's|(cluster_domain: ")[^"]*"|\1<cluster-domain-redacted>"|g')
  content=$(echo "$content" | sed -E \
    's|(cluster_domain: )([^ ].+)$|\1<cluster-domain-redacted>|g')

  # 2. Replace node_names with positional aliases (node-0, node-1, ...)
  # Extract the node list value and replace each name
  if echo "$content" | grep -qE 'node_names:'; then
    # Handle YAML inline list: node_names: [name1, name2, name3]
    local names_line
    names_line=$(echo "$content" | grep 'node_names:' | head -1)
    if echo "$names_line" | grep -qE '\[.+\]'; then
      local names_csv
      names_csv=$(echo "$names_line" | sed -E 's/.*\[(.+)\].*/\1/')
      local sanitized_list=""
      local idx=0
      IFS=', ' read -ra name_arr <<< "$(echo "$names_csv" | tr -d '"')"
      for name in "${name_arr[@]}"; do
        [[ -z "$name" ]] && continue
        sanitized_list+="\"node-${idx}\", "
        # Also replace any occurrence of this name elsewhere in the file
        content=$(echo "$content" | sed "s|$name|node-${idx}|g")
        ((idx++)) || true
      done
      sanitized_list="${sanitized_list%, }"
      content=$(echo "$content" | sed -E \
        "s|node_names: \[.*\]|node_names: [$sanitized_list]|")
    fi
  fi

  # 3. Scrub failure_detail — redact FQDNs and IPs in error messages
  # Replace FQDN-like strings with <hostname-redacted>
  content=$(echo "$content" | sed -E \
    's|([a-z0-9-]+\.){2,}[a-z]{2,}|<hostname-redacted>|g')

  # Replace bare IPs
  content=$(echo "$content" | sed -E \
    's|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|<ip-redacted>|g')

  # 4. Add sanitization header
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local header="# Sanitized learning journal — sensitive data redacted at $ts"$'\n'
  header+="# Original: $(basename "$INPUT")"$'\n'

  echo "$header"
  echo "$content"
}

# ── Output ────────────────────────────────────────────────────────────────────
if [[ -n "$OUTPUT" ]]; then
  sanitize > "$OUTPUT"
  echo "Sanitized journal written to: $OUTPUT"

  # Verify no sensitive patterns remain
  if ! bash "$0" --check "$OUTPUT" 2>/dev/null; then
    echo "WARNING: Sanitized output may still contain sensitive patterns. Review before committing." >&2
  fi
else
  sanitize
fi
