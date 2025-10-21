#!/usr/bin/env bash
set -euo pipefail
# ==============================================================================
# Instana Agent — OFFLINE IMPORT & INSTALL (v2.3)
#
# Enhancements in this version:
# - Clean engine selection: --engine {auto|podman|skopeo} (default: auto)
# - If engine=podman → only podman is used; if engine=skopeo → only skopeo is used.
# - In auto mode → prefer podman; if podman load fails and skopeo is present, fallback to skopeo for that image.
#
# What this script does:
#   1) Push images from the offline kit into your OpenShift internal registry.
#   2) Apply Instana chart CRDs (v2 chart requires CRDs present before Helm).
#   3) Helm upgrade --install the Instana chart, pointing to your internal registry.
#
# Why CRDs first?
#   Helm has known CRD lifecycle limitations; Instana v2 chart deploys an Operator
#   that reconciles an Agent Custom Resource rendered by Helm. CRDs must exist
#   before Helm renders the CR, otherwise the CR is rejected. Instana’s notes for
#   v2 explicitly recommend applying CRDs first, then running Helm.  [1][2]
#
# References:
# [1] Instana Helm chart readme & model (operator deploys agent/k8sensor)
#     https://github.com/instana/helm-charts/blob/main/instana-agent/README.md
# [2] Instana v2 chart release notes (apply CRDs first / controllerManager.image overrides)
#     https://www.ibm.com/docs/en/instana-observability/1.0.306?topic=agent-helm-chart
# [3] Required agent values and post-install checks
#     https://www.ibm.com/docs/en/instana-observability/1.0.306?topic=kubernetes-administering-agent
# ==============================================================================

die()   { echo "FATAL: $*"   >&2; exit 1; }
warn()  { echo "WARNING: $*" >&2; }
log()   { echo ">>> $*"; }

# ------------------------- CLI defaults -------------------------
KIT_DIR=""
NAMESPACE="instana-agent"
CLUSTER_NAME=""
ZONE_NAME=""
ENDPOINT_HOST=""
ENDPOINT_PORT="443"
AGENT_KEY=""
REGISTRY_HOST=""         # internal registry route; auto-detected if empty
INSECURE_REGISTRY="false"
USE_SKOPEO="false"

# Tags to publish into internal registry (mapping.csv source tags are kept unless overridden)
AGENT_TAG="latest"
SENSOR_TAG="latest"
OPERATOR_TAG="latest"

# Repo name to store the *agent* image under, default "instana-agent"
# (even if the source was ".../release/agent/static", we tag to /<ns>/instana-agent:<tag>)
AGENT_REPO_NAME="instana-agent"
CHART_TGZ=""
PUSH_ONLY="false"
INSTALL_ONLY="false"
RELEASE_NAME="instana-agent"

usage() {
  cat <<EOF
Usage: $0 --kit-dir DIR [options]
Required:
  --kit-dir DIR            Path to the offline kit directory (with charts/, images/, metadata/)
Options:
  --namespace NAME         Target namespace/project (default: instana-agent)
  --cluster-name NAME      Cluster display name in Instana
  --zone-name NAME         Zone label in Instana
  --endpoint-host HOST     Instana backend host (required for working agents)
  --endpoint-port PORT     Instana backend port (default: 443)
  --agent-key KEY          Instana agent key (required for working agents)
  --registry HOST          Internal registry route (auto-detect if omitted)
  --insecure-registry      Skip TLS verification when pushing to internal registry
  --agent-tag TAG          Tag to push/consume for agent (default: latest)
  --sensor-tag TAG         Tag to push/consume for k8sensor (default: latest)
  --operator-tag TAG       Tag to push/consume for operator (default: latest)
  --agent-repo-name NAME   Repo name to use for agent in internal registry (default: instana-agent)
  --chart FILE.tgz         Chart archive (auto-detect from kit if omitted)
  --push-only              Only push images (skip Helm install/upgrade)
  --install-only           Only install/upgrade (skip image pushes)
  --engine MODE            Image engine: auto | podman | skopeo (default: auto)
  -h|--help                This help
Notes:
- The Instana Helm chart (v2) deploys an Operator, which creates the Agent DaemonSet
  and the k8sensor Deployment from an Agent Custom Resource rendered by Helm. [1]
- CRDs must be present BEFORE Helm renders the CR; we apply chart CRDs first. [2]
- The agent requires agent.key and endpointHost/Port to connect successfully. [3]
EOF
}

# ------------------------- Parse arguments -------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kit-dir)            KIT_DIR="$2"; shift 2;;
    --namespace)          NAMESPACE="$2"; shift 2;;
    --cluster-name)       CLUSTER_NAME="$2"; shift 2;;
    --zone-name)          ZONE_NAME="$2"; shift 2;;
    --endpoint-host)      ENDPOINT_HOST="$2"; shift 2;;
    --endpoint-port)      ENDPOINT_PORT="$2"; shift 2;;
    --agent-key)          AGENT_KEY="$2"; shift 2;;
    --registry)           REGISTRY_HOST="$2"; shift 2;;
    --insecure-registry)  INSECURE_REGISTRY="true"; shift 1;;
    --agent-tag)          AGENT_TAG="$2"; shift 2;;
    --sensor-tag)         SENSOR_TAG="$2"; shift 2;;
    --operator-tag)       OPERATOR_TAG="$2"; shift 2;;
    --agent-repo-name)    AGENT_REPO_NAME="$2"; shift 2;;
    --chart)              CHART_TGZ="$2"; shift 2;;
    --push-only)          PUSH_ONLY="true"; shift 1;;
    --install-only)       INSTALL_ONLY="true"; shift 1;;
    --engine)             ENGINE="$2"; shift 2;;
    -h|--help)            usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "${KIT_DIR}" ]] || die "--kit-dir is required"
[[ -d "${KIT_DIR}" ]] || die "--kit-dir '${KIT_DIR}' not found"

need_bin() { command -v "$1" >/dev/null 2>&1 || die "Missing required binary: $1"; }
need_bin oc
need_bin helm

# Decide engine
case "${ENGINE}" in
  auto)
    if command -v podman >/dev/null 2>&1; then
      ENGINE="podman"
    elif command -v skopeo >/dev/null 2>&1; then
      ENGINE="skopeo"
    else
      die "Neither podman nor skopeo found; install one or set --engine accordingly"
    fi
    ;;
  podman)
    need_bin podman
    ;;
  skopeo)
    need_bin skopeo
    ;;
  *) die "Invalid --engine '${ENGINE}', expected auto|podman|skopeo";;
esac

oc whoami >/dev/null 2>&1 || die "You must be logged in with 'oc login'"
log "Using namespace: ${NAMESPACE}"
oc new-project "${NAMESPACE}" >/dev/null 2>&1 || true

# ------------------------- Internal registry discovery/login -------------------------
if [[ -z "${REGISTRY_HOST}" ]]; then
  REGISTRY_HOST="$(oc get route default-route -n openshift-image-registry \
    -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -z "${REGISTRY_HOST}" ]]; then
    log "Enabling defaultRoute on the OpenShift internal registry"
    oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
      -p '{"spec":{"defaultRoute":true}}' >/dev/null
    log "Waiting for default-route to appear..."
    for _ in {1..60}; do
      REGISTRY_HOST="$(oc get route default-route -n openshift-image-registry \
        -o jsonpath='{.spec.host}' 2>/dev/null || true)"
      [[ -n "${REGISTRY_HOST}" ]] && break
      sleep 2
    done
    [[ -n "${REGISTRY_HOST}" ]] || die "default-route not available"
  fi
fi
log "Internal registry: ${REGISTRY_HOST}"

TLSFLAG=( "--tls-verify=true" )
SKOPEO_TLS="--dest-tls-verify=true"
if [[ "${INSECURE_REGISTRY}" == "true" ]]; then
  TLSFLAG=( "--tls-verify=false" )
  SKOPEO_TLS="--dest-tls-verify=false"
fi

if [[ "${ENGINE}" == "podman" ]]; then
  log "Logging into internal registry with OpenShift token (podman)"
  podman login "${TLSFLAG[@]}" -u kubeadmin -p "$(oc whoami -t)" "${REGISTRY_HOST}" >/dev/null
else
  log "Using skopeo with --dest-creds; no podman login required"
fi

# Grant SCCs required by Instana on OpenShift (idempotent)
oc adm policy add-scc-to-user privileged -z instana-agent -n "${NAMESPACE}" >/dev/null || true
oc adm policy add-scc-to-user anyuid -z instana-agent-remote -n "${NAMESPACE}" >/dev/null || true

# ------------------------------ Push images from kit ------------------------------
# Compute destination ref and per-image tag override; independent of engine.
map_dest() {
  local SRC_REF="$1"
  local NAME_NO_TAG="${SRC_REF%:*}"
  local SRC_TAG="${SRC_REF##*:}"
  local BASE_COMP
  BASE_COMP="$(basename "${NAME_NO_TAG}")"
  local DEST_REPO DEST_TAG
  case "${BASE_COMP}" in
    static|dynamic|agent) DEST_REPO="${AGENT_REPO_NAME}";;
    k8sensor) DEST_REPO="k8sensor";;
    instana-agent-operator) DEST_REPO="instana-agent-operator";;
    *) DEST_REPO="${BASE_COMP}";;
  esac
  case "${DEST_REPO}" in
    "${AGENT_REPO_NAME}") DEST_TAG="${AGENT_TAG}";;
    k8sensor) DEST_TAG="${SENSOR_TAG}";;
    instana-agent-operator) DEST_TAG="${OPERATOR_TAG}";;
    *) DEST_TAG="${SRC_TAG}";;
  esac
  printf '%s\n' "${REGISTRY_HOST}/${NAMESPACE}/${DEST_REPO}:${DEST_TAG}"
}

push_with_podman() {
  local TAR_PATH="$1"; local DEST_REF="$2"; local SRC_REF="$3"
  echo " -> podman load: $(basename "${TAR_PATH}")"
  if podman load -i "${TAR_PATH}" >/tmp/podman_load.out 2>/tmp/podman_load.err; then
    local LOADED
    LOADED="$(awk '/Loaded image:/ {print $3}' /tmp/podman_load.out | tail -n1)"
    [[ -z "${LOADED}" ]] && LOADED="${SRC_REF}"
    echo "    Loaded as: ${LOADED}"
    echo "    Tagging -> ${DEST_REF}"
    podman tag "${LOADED}" "${DEST_REF}" || true
    echo "    Pushing -> ${DEST_REF}"
    podman push "${TLSFLAG[@]}" "${DEST_REF}" >/dev/null
    return 0
  else
    return 1
  fi
}

push_with_skopeo() {
  local TAR_PATH="$1"; local DEST_REF="$2"
  echo " -> skopeo copy docker-archive -> ${DEST_REF}"
  skopeo copy --insecure-policy docker-archive:"${TAR_PATH}" \
    docker://"${DEST_REF}" \
    --dest-creds "kubeadmin:$(oc whoami -t)" \
    ${SKOPEO_TLS} >/dev/null
}

push_one() {
  local TAR_PATH="$1"; local SRC_REF="$2"
  local DEST_REF
  DEST_REF="$(map_dest "${SRC_REF}")"

  # quick format probe (not fatal if missing)
  if ! tar -tf "${TAR_PATH}" manifest.json >/dev/null 2>&1; then
    warn "manifest.json not found in ${TAR_PATH}; not a docker-archive? proceeding"
  fi

  case "${ENGINE}" in
    podman)
      push_with_podman "${TAR_PATH}" "${DEST_REF}" "${SRC_REF}" || die "podman failed to load/push $(basename "${TAR_PATH}")"
      ;;
    skopeo)
      push_with_skopeo "${TAR_PATH}" "${DEST_REF}"
      ;;
    auto|*)
      # Should not hit here because we resolved ENGINE earlier, but keep as safety:
      if command -v podman >/dev/null 2>&1; then
        if push_with_podman "${TAR_PATH}" "${DEST_REF}" "${SRC_REF}"; then
          return 0
        elif command -v skopeo >/dev/null 2>&1; then
          warn "podman load failed; falling back to skopeo for $(basename "${TAR_PATH}")"
          push_with_skopeo "${TAR_PATH}" "${DEST_REF}"
        else
          die "podman load failed and skopeo not available"
        fi
      elif command -v skopeo >/dev/null 2>&1; then
        push_with_skopeo "${TAR_PATH}" "${DEST_REF}"
      else
        die "No engine available"
      fi
      ;;
  esac
}

if [[ "${INSTALL_ONLY}" != "true" ]]; then
  MAPPING="${KIT_DIR}/metadata/mapping.csv"
  [[ -f "${MAPPING}" ]] || die "mapping.csv not found at ${MAPPING}"
  log "Pushing images from kit ..."
  while IFS=, read -r SRC SAFE; do
    TAR="${KIT_DIR}/images/${SAFE}.tar"
    [[ -f "${TAR}" ]] || die "Missing tarball: ${TAR} (from mapping ${SAFE})"
    push_one "${TAR}" "${SRC}"
  done < "${MAPPING}"
  log "Image push complete."
fi

# ------------------------------ Auto-detect a non-latest operator tag if not supplied ------------------------------
if [[ "${OPERATOR_TAG}" == "latest" ]]; then
  DETECTED="$(awk -F, '/instana-agent-operator/ && $1 ~ /icr.io\/instana\/instana-agent-operator:/ { split($1,a,":"); if (a[2]!="latest") print a[2] }' "${KIT_DIR}/metadata/mapping.csv" | head -n1 || true)"
  if [[ -n "${DETECTED}" ]]; then
    OPERATOR_TAG="${DETECTED}"
    log "Auto-detected operator tag: ${OPERATOR_TAG}"
  else
    warn "No non-latest operator tag found in kit; continuing with :latest (not recommended)."
  fi
fi

# ------------------------------ Helm install/upgrade ------------------------------
if [[ "${PUSH_ONLY}" != "true" ]]; then
  if [[ -z "${CHART_TGZ}" ]]; then
    CHART_TGZ="$(ls -1 "${KIT_DIR}"/charts/instana-agent-*.tgz 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "${CHART_TGZ}" && -f "${CHART_TGZ}" ]] || die "Could not find instana-agent chart archive under ${KIT_DIR}/charts (use --chart)"
  if [[ -z "${AGENT_KEY}" ]]; then warn "--agent-key is empty; agents will not connect"; fi
  if [[ -z "${ENDPOINT_HOST}" ]]; then warn "--endpoint-host is empty; agents will not connect"; fi

  TMP_CHART_DIR="$(mktemp -d)"
  tar -xzf "${CHART_TGZ}" -C "${TMP_CHART_DIR}"
  if [[ -d "${TMP_CHART_DIR}/instana-agent/crds" ]]; then
    log "Applying CRDs from chart (instana-agent/crds)"
    oc apply -f "${TMP_CHART_DIR}/instana-agent/crds"
  elif [[ -d "${TMP_CHART_DIR}/crds" ]]; then
    log "Applying CRDs from chart (crds)"
    oc apply -f "${TMP_CHART_DIR}/crds"
  else
    warn "No CRDs directory found inside chart archive; continuing"
  fi

  VALUES_FILE="$(mktemp)"
  cat > "${VALUES_FILE}" <<YAML
agent:
  key: "${AGENT_KEY}"
  endpointHost: "${ENDPOINT_HOST}"
  endpointPort: ${ENDPOINT_PORT}
  image:
    name: "${REGISTRY_HOST}/${NAMESPACE}/${AGENT_REPO_NAME}"
    tag: "${AGENT_TAG}"
k8s_sensor:
  image:
    name: "${REGISTRY_HOST}/${NAMESPACE}/k8sensor"
    tag: "${SENSOR_TAG}"
controllerManager:
  image:
    name: "${REGISTRY_HOST}/${NAMESPACE}/instana-agent-operator"
    tag: "${OPERATOR_TAG}"
cluster:
  name: "${CLUSTER_NAME}"
zone:
  name: "${ZONE_NAME}"
YAML

  log "Helm upgrade --install ${RELEASE_NAME} in ${NAMESPACE}"
  helm upgrade --install "${RELEASE_NAME}" "${CHART_TGZ}" \
    --namespace "${NAMESPACE}" --create-namespace \
    -f "${VALUES_FILE}"

  log "Waiting for operator pod to be ready..."
  oc rollout status deploy/instana-agent-controller-manager -n "${NAMESPACE}" --timeout=180s || true
  log "Checking Agent CR presence and status..."
  if oc api-resources | grep -qiE '^agent(\.|s)\s'; then
    oc get agent -n "${NAMESPACE}" || true
    if command -v yq >/dev/null 2>&1; then
      oc get agent -n "${NAMESPACE}" -o yaml | yq '.items[?].status' || true
    fi
  else
    oc get instanaagent -n "${NAMESPACE}" || true
  fi
  log "Pods in ${NAMESPACE}:"
  oc get pods -n "${NAMESPACE}"
fi

log "DONE. Verify with: oc -n ${NAMESPACE} get pods"
