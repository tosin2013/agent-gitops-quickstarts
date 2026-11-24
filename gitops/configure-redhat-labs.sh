#!/usr/bin/env bash
# Configure a multi-node OpenShift cluster for Day 2 operations.
#
# Execution order (each step waits for the previous to complete):
#   1. Wait for cluster health (all operators Available, no Degraded)
#   2. Configure monitoring (pin Prometheus to non-ODF workers, set resource limits)
#   3. Install cert-manager + issue *.apps wildcard cert (optional, --configure-certs)
#   4. Bootstrap ArgoCD
#   5. Label infra/storage nodes (--configure-infra-nodes)
#   6. Install LSO + ODF (--configure-storage)
#   7. Deploy profile (kvm-ocp-virt or interactive)
#
# Supports any node naming convention and OCP version.
# With --learn, writes an execution journal that the learn-environment agent uses
# to automatically improve skills, overlays, and profiles for new environment types.
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
DEFAULT_OCP_VERSION="4.22"
DEFAULT_TIMEOUT=600   # increased from 300 — ArgoCD operator download can take 5-10min
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/sno-quickstarts")"
KUSTOMIZE_INSTALL_SCRIPT="https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
LEARNINGS_DIR="$REPO_ROOT/gitops/learnings"

# ── Runtime state ─────────────────────────────────────────────────────────────
OCP_VERSION="$DEFAULT_OCP_VERSION"
NODES=""                   # comma-separated; auto-discovered if empty
ODF_INSTANCE_OVERLAY=""    # auto-selected if empty
PROFILE_NAME=""            # if empty, show interactive menu
CONFIGURE_INFRA_NODES=false
CONFIGURE_STORAGE=false
CONFIGURE_CERTS=false
CONFIGURE_MONITORING=true       # always on — prevents Prometheus competing with Ceph
MONITORING_NODES=""             # comma-separated non-ODF workers; auto-detected if empty
CERT_EMAIL=""                   # required for --configure-certs
CERT_ZONE_ID=""                 # Route53 hosted zone ID
CERT_REGION="us-east-1"
LEARN=false
DRY_RUN=false
DEBUG=false
TIMEOUT=$DEFAULT_TIMEOUT

STEPS_COMPLETED=()
OUTCOME="unknown"
FAILURE_DETAIL=""

# ── Logging ──────────────────────────────────────────────────────────────────
log()   { echo "[$(date '+%H:%M:%S')] $*"; }
debug() { [[ "$DEBUG" == "true" ]] && echo "[DEBUG] $*" || true; }
warn()  { echo "[WARN]  $*" >&2; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

dry() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Configure a multi-node OpenShift cluster for Day 2 GitOps operations.

Options:
  --configure-infra-nodes        Label worker nodes as infra/storage nodes
  --configure-storage            Install Local Storage Operator + ODF
  --nodes node1,node2,node3      Storage node names (default: auto-discover workers)
  --ocp-version 4.22             OCP version for operator channel selection (default: $DEFAULT_OCP_VERSION)
  --odf-instance-overlay <name>  ODF StorageCluster overlay (default: auto-select by platform)
  --profile <name>               Deploy this profile non-interactively
  --learn                        Enable self-learning mode: write execution journal
  --dry-run                      Print what would happen without making changes
  --debug                        Enable verbose debug output
  --timeout <seconds>            Operation timeout in seconds (default: $DEFAULT_TIMEOUT)
  -h, --help                     Show this help

Examples:
  # Auto-discover nodes, use current OCP version:
  $(basename "$0") --configure-infra-nodes --configure-storage

  # Explicit nodes and version:
  $(basename "$0") --configure-storage --nodes worker-0,worker-1,worker-2 --ocp-version 4.22

  # Non-interactive with self-learning:
  $(basename "$0") --configure-infra-nodes --configure-storage --profile kvm-ocp-virt --learn

  # Dry run to preview changes:
  $(basename "$0") --configure-storage --nodes lab-worker-0,lab-worker-1,lab-worker-2 --dry-run
EOF
}

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --configure-infra-nodes) CONFIGURE_INFRA_NODES=true ;;
    --configure-storage)     CONFIGURE_STORAGE=true ;;
    --configure-certs)       CONFIGURE_CERTS=true ;;
    --no-monitoring)         CONFIGURE_MONITORING=false ;;
    --monitoring-nodes)      MONITORING_NODES="$2"; shift ;;
    --cert-email)            CERT_EMAIL="$2"; shift ;;
    --cert-zone-id)          CERT_ZONE_ID="$2"; shift ;;
    --cert-region)           CERT_REGION="$2"; shift ;;
    --nodes)                 NODES="$2"; shift ;;
    --ocp-version)           OCP_VERSION="$2"; shift ;;
    --odf-instance-overlay)  ODF_INSTANCE_OVERLAY="$2"; shift ;;
    --profile)               PROFILE_NAME="$2"; shift ;;
    --learn)                 LEARN=true ;;
    --dry-run)               DRY_RUN=true ;;
    --debug)                 DEBUG=true ;;
    --timeout)               TIMEOUT="$2"; shift ;;
    -h|--help)               usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  die "Not logged in to OpenShift. Run 'oc login' first."
fi

# Install kustomize if missing (oc kustomize is a fallback but standalone is preferred)
if ! command -v kustomize &>/dev/null && [[ ! -f /usr/local/bin/kustomize ]]; then
  if ! $DRY_RUN; then
    log "Installing kustomize..."
    curl -s "$KUSTOMIZE_INSTALL_SCRIPT" | bash
    sudo mv kustomize /usr/local/bin/kustomize
  fi
fi

# ── Environment fingerprinting ────────────────────────────────────────────────
fingerprint_environment() {
  PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platform}' 2>/dev/null || echo "Unknown")
  OCP_DETECTED=$(oc version 2>/dev/null | grep "Server Version" | awk '{print $3}' | cut -d. -f1-2 || echo "$OCP_VERSION")
  CLUSTER_DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "unknown")

  # Auto-discover worker nodes if --nodes not supplied
  if [[ -z "$NODES" ]]; then
    log "Auto-discovering worker nodes..."
    NODES=$(oc get nodes -l node-role.kubernetes.io/worker \
      --no-headers -o custom-columns='NAME:.metadata.name' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    if [[ -z "$NODES" ]]; then
      # Fall back to any non-master node
      NODES=$(oc get nodes --no-headers \
        -o custom-columns='NAME:.metadata.name,ROLES:.metadata.labels' 2>/dev/null \
        | grep -v master | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
    fi
    log "Discovered nodes: $NODES"
  fi

  NODE_COUNT=$(echo "$NODES" | tr ',' '\n' | grep -c .)
  # Extract the non-numeric prefix to identify naming convention
  FIRST_NODE=$(echo "$NODES" | cut -d, -f1)
  NODE_PATTERN=$(echo "$FIRST_NODE" | sed 's/[0-9]*$//')

  # Classify environment type from node pattern + platform
  case "$NODE_PATTERN" in
    *lab-worker*)   ENV_TYPE="red-hat-labs" ;;
    *equinix*)      ENV_TYPE="equinix-metal" ;;
    *vsphere*|*esxi*) ENV_TYPE="vsphere" ;;
    *)
      case "$PLATFORM" in
        AWS)      ENV_TYPE="aws" ;;
        GCP)      ENV_TYPE="gcp" ;;
        Azure)    ENV_TYPE="azure" ;;
        VSphere)  ENV_TYPE="vsphere" ;;
        None)     ENV_TYPE="bare-metal-or-kvm" ;;
        *)        ENV_TYPE="unknown-${PLATFORM,,}" ;;
      esac
      ;;
  esac

  # Gather cloud-specific metadata for richer learning journals
  CLOUD_REGION=""
  CLOUD_INSTANCE_TYPE=""
  case "$PLATFORM" in
    AWS)
      CLOUD_REGION=$(oc get infrastructure cluster \
        -o jsonpath='{.status.platformStatus.aws.region}' 2>/dev/null || echo "")
      # Get instance type from first worker node
      CLOUD_INSTANCE_TYPE=$(oc get nodes -l node-role.kubernetes.io/worker \
        --no-headers -o jsonpath='{.items[0].metadata.labels.beta\.kubernetes\.io/instance-type}' \
        2>/dev/null || echo "")
      ;;
    GCP)
      CLOUD_REGION=$(oc get infrastructure cluster \
        -o jsonpath='{.status.platformStatus.gcp.region}' 2>/dev/null || echo "")
      CLOUD_INSTANCE_TYPE=$(oc get nodes -l node-role.kubernetes.io/worker \
        --no-headers -o jsonpath='{.items[0].metadata.labels.beta\.kubernetes\.io/instance-type}' \
        2>/dev/null || echo "")
      ;;
    Azure)
      CLOUD_REGION=$(oc get infrastructure cluster \
        -o jsonpath='{.status.platformStatus.azure.resourceGroupName}' 2>/dev/null || echo "")
      ;;
  esac

  # Auto-select ODF instance overlay if not supplied
  if [[ -z "$ODF_INSTANCE_OVERLAY" ]]; then
    case "$ENV_TYPE" in
      aws)            ODF_INSTANCE_OVERLAY="aws" ;;
      gcp)            ODF_INSTANCE_OVERLAY="gcp" ;;
      azure)          ODF_INSTANCE_OVERLAY="azure" ;;
      vsphere)        ODF_INSTANCE_OVERLAY="vsphere" ;;
      equinix-metal)  ODF_INSTANCE_OVERLAY="equinix-cnv" ;;
      *)              ODF_INSTANCE_OVERLAY="bare-metal" ;;
    esac
    log "Auto-selected ODF instance overlay: $ODF_INSTANCE_OVERLAY"
  fi

  debug "Environment: platform=$PLATFORM ocp=$OCP_DETECTED type=$ENV_TYPE nodes=$NODES"
}

# ── Pod wait helper ──────────────────────────────────────────────────────────
wait_for_pod() {
  local pattern="$1" namespace="$2" timeout="${3:-$TIMEOUT}"
  local end=$(($(date +%s) + timeout))
  log "Waiting for pod matching '$pattern' in $namespace (timeout: ${timeout}s)..."
  while [[ $(date +%s) -lt $end ]]; do
    local pod
    pod=$(oc get pods -n "$namespace" 2>/dev/null | grep "$pattern" | awk '{print $1}' | head -1)
    if [[ -n "$pod" ]]; then
      local ready
      ready=$(oc get pod "$pod" -n "$namespace" \
        -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      if [[ "$ready" == "True" ]]; then
        log "Pod '$pod' is Ready."
        return 0
      fi
    fi
    sleep 10
  done
  warn "Timeout waiting for $pattern in $namespace"
  return 1
}

# ── Cluster health gate ──────────────────────────────────────────────────────
# Wait until all ClusterOperators are Available=True, Progressing=False, Degraded=False.
# This MUST run before any Day 2 operations — doing cert rotation, monitoring migration,
# and GitOps simultaneously while operators are still rolling causes control plane overload.
wait_for_cluster_healthy() {
  local timeout="${1:-900}"   # 15 min default
  local end=$(($(date +%s) + timeout))
  log "Waiting for all cluster operators to be healthy (timeout: ${timeout}s)..."
  log "  This prevents Day 2 operations from overloading a cluster mid-rollout."

  while [[ $(date +%s) -lt $end ]]; do
    local degraded progressing unavailable
    degraded=$(oc get co --no-headers 2>/dev/null | awk '$5=="True"{print $1}' | wc -l)
    progressing=$(oc get co --no-headers 2>/dev/null | awk '$4=="True"{print $1}' | wc -l)
    unavailable=$(oc get co --no-headers 2>/dev/null | awk '$3=="False"{print $1}' | wc -l)

    if [[ "$degraded" -eq 0 && "$progressing" -eq 0 && "$unavailable" -eq 0 ]]; then
      log "✅ All cluster operators healthy."
      STEPS_COMPLETED+=("cluster-health-gate")
      return 0
    fi

    log "  Degraded=$degraded Progressing=$progressing Unavailable=$unavailable — waiting 30s..."
    sleep 30
  done
  warn "Cluster did not become fully healthy within ${timeout}s — proceeding anyway."
}

# ── Monitoring configuration ──────────────────────────────────────────────────
# Pin Prometheus/Alertmanager to non-ODF workers and set resource limits.
# Without this, Prometheus competes with Ceph OSDs for CPU, causing load spikes
# that crash the kube-apiserver (context deadline exceeded / etcd timeout).
#
# Ref: https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/monitoring/configuring-monitoring-stack
configure_monitoring() {
  log "Configuring cluster monitoring (pinning Prometheus to non-ODF workers)..."

  # Auto-detect monitoring nodes: last N workers (non-ODF ones)
  if [[ -z "$MONITORING_NODES" ]]; then
    local all_workers odf_nodes odf_count monitoring_node_list
    all_workers=$(oc get nodes -l node-role.kubernetes.io/worker \
      --no-headers -o custom-columns='NAME:.metadata.name' 2>/dev/null)
    odf_count=$(echo "$NODES" | tr ',' '\n' | grep -c . || echo 3)
    # Non-ODF workers = all workers minus the first N (ODF) ones
    monitoring_node_list=$(echo "$all_workers" | tail -n +"$((odf_count + 1))" | head -3 | tr '\n' ',')
    MONITORING_NODES="${monitoring_node_list%,}"
    log "  Auto-detected monitoring nodes: $MONITORING_NODES"
  fi

  if [[ -z "$MONITORING_NODES" ]]; then
    warn "No non-ODF worker nodes found — monitoring config skipped."
    return 0
  fi

  # Label the monitoring nodes
  IFS=',' read -ra MON_NODES <<< "$MONITORING_NODES"
  for node in "${MON_NODES[@]}"; do
    dry "oc label node '$node' monitoring-node=true --overwrite"
  done

  # Apply ClusterMonitoring configmap
  if ! $DRY_RUN; then
    oc apply -f - << 'MONEOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      nodeSelector:
        monitoring-node: "true"
      resources:
        requests:
          cpu: 200m
          memory: 2Gi
        limits:
          cpu: 4000m
          memory: 8Gi
      retention: 24h
      retentionSize: 20GB
    alertmanagerMain:
      nodeSelector:
        monitoring-node: "true"
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    thanosQuerier:
      nodeSelector:
        monitoring-node: "true"
    prometheusOperator:
      nodeSelector:
        monitoring-node: "true"
MONEOF
    log "✅ Monitoring pinned to: $MONITORING_NODES"
    log "  Waiting 60s for monitoring pods to migrate..."
    sleep 60
  fi

  STEPS_COMPLETED+=("monitoring-config")
}

# ── cert-manager + *.apps cert ────────────────────────────────────────────────
# Install cert-manager and issue a Let's Encrypt wildcard cert for *.apps.
# Must run BEFORE GitOps so the ingress cert is in place before the console
# is fully configured. Does NOT rotate the API server cert (--include-api flag
# risks kubelet auth breakage on baremetal).
#
# Ref: openshift-5-deployment-notes/post-steps/create_custom_cert.sh
configure_certs() {
  if [[ -z "$CERT_EMAIL" || -z "$CERT_ZONE_ID" ]]; then
    warn "--configure-certs requires --cert-email and --cert-zone-id. Skipping."
    return 0
  fi

  log "Installing cert-manager and issuing *.apps Let's Encrypt cert..."

  # Locate openshift-5-deployment-notes repo — check common locations
  local cert_manager_dir="${OCP5_NOTES_DIR:-}"
  if [[ -z "$cert_manager_dir" ]]; then
    for candidate in \
      "$HOME/openshift-5-deployment-notes" \
      "/tmp/openshift-5-deployment-notes" \
      "$REPO_ROOT/../openshift-5-deployment-notes" \
      "$REPO_ROOT/../../openshift-5-deployment-notes"; do
      if [[ -d "$candidate/post-steps" ]]; then
        cert_manager_dir="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$cert_manager_dir" || ! -d "$cert_manager_dir" ]]; then
    warn "openshift-5-deployment-notes repo not found. Set OCP5_NOTES_DIR=/path/to/repo or clone it first."
    warn "  git clone https://github.com/tosin2013/openshift-5-deployment-notes /tmp/openshift-5-deployment-notes"
    warn "Skipping cert-manager configuration."
    return 0
  fi
  log "Using openshift-5-deployment-notes at: $cert_manager_dir"

  dry "oc apply -k '$cert_manager_dir/cert-manager/operator/overlays/stable-v1'"

  if ! $DRY_RUN; then
    log "  Waiting for cert-manager CSV to reach Succeeded..."
    until oc get csv -n cert-manager-operator 2>/dev/null | grep -q "Succeeded"; do
      sleep 15
    done

    # Create CertManager CR if not present
    oc apply -f - 2>/dev/null << 'CMEOF' || true
apiVersion: operator.openshift.io/v1alpha1
kind: CertManager
metadata:
  name: cluster
spec:
  managementState: Managed
  controllerConfig:
    overrideArgs:
    - "--dns01-recursive-nameservers-only"
    - "--dns01-recursive-nameservers=1.1.1.1:53"
CMEOF

    log "  Waiting for cert-manager pods..."
    until oc get pods -n cert-manager 2>/dev/null | grep -c "Running" | grep -qE "^[3-9]"; do
      sleep 10
    done

    log "  Issuing *.apps certificate via Route53 DNS01..."
    bash "$cert_manager_dir/post-steps/create_custom_cert.sh" \
      "$(aws configure get aws_access_key_id)" \
      "$(aws configure get aws_secret_access_key)" \
      "$CERT_EMAIL" \
      "$CERT_ZONE_ID" \
      "$CERT_REGION" 2>&1 || warn "Cert issuance failed — continuing without custom cert."
  fi

  log "✅ cert-manager configuration complete."
  STEPS_COMPLETED+=("cert-manager")
}

# ── ArgoCD bootstrap ─────────────────────────────────────────────────────────
configure_argocd() {
  log "Checking ArgoCD status..."

  if oc get namespace openshift-gitops &>/dev/null; then
    local ready
    ready=$(oc get pods -l app.kubernetes.io/name=openshift-gitops-repo-server \
      -n openshift-gitops \
      -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$ready" == "True" ]]; then
      log "ArgoCD already running and ready. Skipping bootstrap."
      STEPS_COMPLETED+=("argocd-skipped-already-running")
      return 0
    fi
  fi

  log "Bootstrapping ArgoCD..."
  local gitops_path="$REPO_ROOT/gitops/cluster-config/openshift-gitops"

  dry "oc create namespace openshift-gitops 2>/dev/null || true"
  dry "oc create -k '$gitops_path' 2>/dev/null || oc apply -k '$gitops_path'"

  if ! $DRY_RUN; then
    # Wait for ArgoCD CRD
    local end=$(($(date +%s) + TIMEOUT))
    until oc get crd/argocds.argoproj.io &>/dev/null; do
      [[ $(date +%s) -lt $end ]] || die "Timeout waiting for ArgoCD CRD"
      sleep 10
    done

    dry "oc apply -k '$gitops_path'"
    wait_for_pod "openshift-gitops-repo-server" "openshift-gitops" "$TIMEOUT" || die "ArgoCD repo server not ready"
  fi

  log "ArgoCD bootstrap complete."
  STEPS_COMPLETED+=("argocd")
}

# ── Infra node labeling ───────────────────────────────────────────────────────
configure_infranodes() {
  log "Labeling infra/storage nodes: $NODES"

  IFS=',' read -ra NODE_ARRAY <<< "$NODES"
  for node in "${NODE_ARRAY[@]}"; do
    dry "oc label node '$node' node-role.kubernetes.io/infra='' --overwrite"
    dry "oc label node '$node' cluster.ocs.openshift.io/openshift-storage='' --overwrite"
  done

  dry "oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
    -p '{\"spec\":{\"nodeSelector\":{\"node-role.kubernetes.io/infra\": \"\"}}}'"

  dry "oc patch ingresscontroller/default -n openshift-ingress-operator --type=merge \
    -p '{\"spec\":{\"nodePlacement\":{\"nodeSelector\":{\"matchLabels\":{\"node-role.kubernetes.io/infra\":\"\"}},\"tolerations\":[{\"effect\":\"NoSchedule\",\"key\":\"node-role.kubernetes.io/infra\",\"value\":\"reserved\"},{\"effect\":\"NoExecute\",\"key\":\"node-role.kubernetes.io/infra\",\"value\":\"reserved\"}]}}}'"

  log "Infra node labeling complete."
  STEPS_COMPLETED+=("infra-nodes")
}

# ── Dynamic local-storage overlay generation ──────────────────────────────────
generate_lso_overlay() {
  # Build a temporary kustomize overlay with the actual node names
  local tmpdir
  tmpdir=$(mktemp -d)

  IFS=',' read -ra NODE_ARRAY <<< "$NODES"
  local node_values=""
  for node in "${NODE_ARRAY[@]}"; do
    node_values+="                  - $node"$'\n'
  done

  cat > "$tmpdir/kustomization.yaml" <<KUST
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: openshift-local-storage
bases:
  - $REPO_ROOT/gitops/cluster-config/openshift-local-storage/instance/base
patches:
- target:
    kind: LocalVolumeDiscovery
    name: auto-discover-devices
  patch: |-
    apiVersion: local.storage.openshift.io/v1alpha1
    kind: LocalVolumeDiscovery
    metadata:
      name: auto-discover-devices
      namespace: openshift-local-storage
    spec:
      nodeSelector:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
${node_values}- target:
    kind: LocalVolumeSet
    name: lolvol
  patch: |-
    apiVersion: local.storage.openshift.io/v1alpha1
    kind: LocalVolumeSet
    metadata:
      name: lolvol
      namespace: openshift-local-storage
    spec:
      nodeSelector:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
${node_values}
KUST

  echo "$tmpdir"
}

# ── Storage configuration ─────────────────────────────────────────────────────
configure_storage() {
  log "Configuring Local Storage Operator + ODF..."
  local lso_op="$REPO_ROOT/gitops/cluster-config/openshift-local-storage/operator/overlays/stable-${OCP_VERSION}"
  local odf_op="$REPO_ROOT/gitops/cluster-config/openshift-data-foundation-operator/operator/overlays/stable-${OCP_VERSION}"
  local odf_inst="$REPO_ROOT/gitops/cluster-config/openshift-data-foundation-operator/instance/overlays/${ODF_INSTANCE_OVERLAY}"

  # Idempotency check
  if ! $DRY_RUN; then
    if oc get storagecluster -n openshift-storage &>/dev/null 2>&1; then
      local phase
      phase=$(oc get storagecluster -n openshift-storage \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
      if [[ "$phase" == "Ready" ]]; then
        log "StorageCluster already Ready. Skipping."
        STEPS_COMPLETED+=("storage-skipped-already-ready")
        return 0
      fi
    fi
  fi

  # Verify overlay paths exist
  [[ -d "$lso_op" ]] || die "LSO overlay not found: $lso_op. Try --ocp-version <version>"
  [[ -d "$odf_op" ]] || die "ODF operator overlay not found: $odf_op"
  [[ -d "$odf_inst" ]] || die "ODF instance overlay not found: $odf_inst"

  dry "oc apply -k '$lso_op'"
  dry "oc apply -k '$odf_op'"

  if ! $DRY_RUN; then
    # Wait for namespaces
    for ns in openshift-local-storage openshift-storage; do
      local end=$(($(date +%s) + TIMEOUT))
      until oc get namespace "$ns" &>/dev/null; do
        [[ $(date +%s) -lt $end ]] || die "Timeout waiting for namespace $ns"
        sleep 10
      done
    done
    wait_for_pod "local-storage-operator" "openshift-local-storage" "$TIMEOUT"
    wait_for_pod "ocs-operator" "openshift-storage" "$TIMEOUT"
  fi

  # Generate dynamic LSO instance overlay with actual node names
  log "Generating local-storage instance overlay for nodes: $NODES"
  local lso_tmpdir
  lso_tmpdir=$(generate_lso_overlay)
  dry "oc create -k '$lso_tmpdir' || oc apply -k '$lso_tmpdir'"

  if ! $DRY_RUN; then
    log "Waiting 30s for local volume discovery..."
    sleep 30
  fi

  dry "oc create -k '$odf_inst' || oc apply -k '$odf_inst'"

  if ! $DRY_RUN; then
    # Verify StorageCluster created
    local end=$(($(date +%s) + 300))
    until oc get storagecluster -n openshift-storage &>/dev/null; do
      [[ $(date +%s) -lt $end ]] || die "Timeout: StorageCluster not created"
      sleep 20
    done
    log "✅ StorageCluster created."
    log "Note: StorageCluster may take several minutes to reach Ready state."
    log "Check: oc get storagecluster -n openshift-storage"
  fi

  log "Storage configuration complete."
  STEPS_COMPLETED+=("storage")
}

# ── Profile deployment ────────────────────────────────────────────────────────
deploy_profile() {
  local apps_dir="$REPO_ROOT/gitops/apps"

  if [[ -n "$PROFILE_NAME" ]]; then
    local profile_yaml="$apps_dir/$PROFILE_NAME/cluster-config.yaml"
    [[ -f "$profile_yaml" ]] || die "Profile not found: $profile_yaml"
    log "Deploying profile: $PROFILE_NAME"
    dry "oc apply -f '$profile_yaml'"
    STEPS_COMPLETED+=("profile:$PROFILE_NAME")
  else
    # Interactive menu
    cd "$apps_dir"
    local options=("Exit" $(find . -maxdepth 1 -type d -not -path '.'))
    select dir in "${options[@]}"; do
      case "$dir" in
        "Exit") log "Exiting profile selection."; break ;;
        *)
          dir="${dir#./}"
          log "Deploying profile: $dir"
          dry "oc apply -f '$dir/cluster-config.yaml'"
          STEPS_COMPLETED+=("profile:$dir")
          break
          ;;
      esac
    done
  fi
}

# ── Execution journal writer ──────────────────────────────────────────────────
write_journal() {
  local ts
  ts=$(date -u '+%Y%m%dT%H%M%SZ')
  # Raw journal — full data, local only (gitignored via *.raw.yaml rule)
  local raw_journal="$LEARNINGS_DIR/${ts}-${ENV_TYPE}.raw.yaml"
  # Sanitized journal — no sensitive data, safe to commit
  local clean_journal="$LEARNINGS_DIR/${ts}-${ENV_TYPE}.yaml"
  local sanitizer="$REPO_ROOT/gitops/sanitize-journal.sh"

  mkdir -p "$LEARNINGS_DIR"

  # Write raw journal with full data (stays local)
  cat > "$raw_journal" <<JOURNAL
# RAW execution journal — NEVER COMMIT THIS FILE (contains sensitive data)
# Created by configure-redhat-labs.sh --learn
# Read by: .claude/agents/learn-environment.md
# Sanitized version: $(basename "$clean_journal")
timestamp: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
env_type: "$ENV_TYPE"
platform: "$PLATFORM"
ocp_version_detected: "$OCP_DETECTED"
ocp_version_used: "$OCP_VERSION"
cluster_domain: "$CLUSTER_DOMAIN"
node_count: $NODE_COUNT
node_pattern: "$NODE_PATTERN"
node_names: [$(echo "$NODES" | sed 's/,/, /g')]
lso_instance_overlay: "generated-runtime-${NODE_PATTERN}N"
odf_instance_overlay: "$ODF_INSTANCE_OVERLAY"
cloud_region: "${CLOUD_REGION:-}"
cloud_instance_type: "${CLOUD_INSTANCE_TYPE:-}"
profile_deployed: "$(echo "${STEPS_COMPLETED[@]}" | grep -oP 'profile:\K[^ ]+' 2>/dev/null || echo 'none')"
steps_completed: [$(printf '"%s", ' "${STEPS_COMPLETED[@]}" | sed 's/, $//')]
outcome: "$OUTCOME"
failure_detail: "$FAILURE_DETAIL"
JOURNAL

  log "Raw journal written (local only): $raw_journal"

  # Produce sanitized version for git commit
  if [[ -x "$sanitizer" ]]; then
    bash "$sanitizer" "$raw_journal" "$clean_journal"
    log "Sanitized journal written (safe to commit): $clean_journal"
  else
    # Fallback: basic scrub if sanitizer not found
    sed -E \
      -e 's|(cluster_domain: ).*$|\1<redacted>|' \
      -e 's|node_names: \[.*\]|node_names: [<redacted>]|' \
      "$raw_journal" > "$clean_journal"
    log "Basic sanitization applied (sanitize-journal.sh not found)"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Self-learning mode: execution journals written."
  echo ""
  echo "  Raw (local only):   $raw_journal"
  echo "  Sanitized (commit): $clean_journal"
  echo ""
  echo "To review and commit the sanitized learning:"
  echo "  git add gitops/learnings/$(basename "$clean_journal")"
  echo "  git commit -m 'docs(learn): add ${ENV_TYPE} environment pattern'"
  echo ""
  echo "To improve skills, overlays, and profiles from this run:"
  echo "  Open Claude Code and say:"
  echo "  'review the latest learning at gitops/learnings/ and update skills'"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ──────────────────────────────────────────────────────────────────────
fingerprint_environment

if $DRY_RUN; then
  echo ""
  echo "DRY RUN — no changes will be made"
  echo "  Environment type:  $ENV_TYPE"
  echo "  Platform:          $PLATFORM"
  echo "  OCP version:       $OCP_VERSION"
  echo "  Nodes:             $NODES"
  echo "  ODF overlay:       $ODF_INSTANCE_OVERLAY"
  echo "  Flags:             infra-nodes=$CONFIGURE_INFRA_NODES storage=$CONFIGURE_STORAGE"
  echo ""
fi

# Step 1: Wait for cluster to be fully healthy before ANY Day 2 operations.
# Doing cert rotation, monitoring migration, and GitOps while operators are
# still rolling causes control plane CPU overload (load 90-117 observed).
if ! $DRY_RUN; then
  wait_for_cluster_healthy 900
fi

# Step 2: Pin monitoring to non-ODF workers and set resource limits.
# Must run before ODF so Prometheus doesn't compete with Ceph OSDs for CPU.
if $CONFIGURE_MONITORING; then
  configure_monitoring || { OUTCOME="failed-at-monitoring"; FAILURE_DETAIL="configure_monitoring failed"; $LEARN && write_journal; warn "Monitoring config failed — continuing"; }
fi

# Step 3: cert-manager + *.apps cert (optional).
# Must run after cluster is healthy but before GitOps so the console cert is ready.
if $CONFIGURE_CERTS; then
  configure_certs || { OUTCOME="failed-at-certs"; FAILURE_DETAIL="configure_certs failed"; $LEARN && write_journal; warn "Cert config failed — continuing"; }
fi

# Step 4: Bootstrap ArgoCD.
configure_argocd || { OUTCOME="failed-at-argocd"; FAILURE_DETAIL="configure_argocd failed"; $LEARN && write_journal; die "ArgoCD bootstrap failed"; }

# Step 5: Label infra/storage nodes.
if $CONFIGURE_INFRA_NODES; then
  configure_infranodes || { OUTCOME="failed-at-infra-nodes"; FAILURE_DETAIL="configure_infranodes failed"; $LEARN && write_journal; die "Infra node labeling failed"; }
fi

# Step 6: Install LSO + ODF.
if $CONFIGURE_STORAGE; then
  configure_storage || { OUTCOME="failed-at-storage"; FAILURE_DETAIL="configure_storage failed"; $LEARN && write_journal; die "Storage configuration failed"; }
fi

# Step 7: Deploy profile.
deploy_profile

OUTCOME="success"
$LEARN && write_journal

log "Done. ✅"
