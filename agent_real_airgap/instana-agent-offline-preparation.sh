#!/usr/bin/env bash
set -euo pipefail
# ==============================================================================
# Instana Agent – OFFLINE PREPARE (v2.1)
# Builds an "offline kit" for installing the Instana Agent on an air‑gapped
# OpenShift/Kubernetes cluster.
#
# Two packaging methods:
#   METHOD="oc-mirror" (recommended for OCP; produces tar + IDMS/ITMS)
#   METHOD="docker"    (simple; per-image docker-archive tars + mapping.csv)
#
# v2.1 highlights:
#   * --instana-agent-key <key> to authenticate pulls from containers.instana.io
#          (user "_" / password = agent key), as per IBM docs.  (Required for agent image)
#   * Seeding now uses:
#       - Operator  : icr.io/instana/instana-agent-operator:<tag>
#       - k8sensor  : icr.io/instana/k8sensor:<tag>
#       - Agent     : containers.instana.io/instana/release/agent/static:<tag>
#   * Skopeo path adds --src-creds (or authfile fallback) automatically for
#     containers.instana.io/* sources. Docker/Podman path logs in once.
#
# References:
# - Instana agent image auth & pull (containers.instana.io, user "_" + agent key)
#   https://www.ibm.com/docs/en/instana-observability/1.0.306?topic=docker-installing-agent
# - Operator image published at icr.io/instana/instana-agent-operator
#   https://artifacthub.io/packages/helm/instana/instana-agent
# ==============================================================================

# ------------------------------ USER CONFIG -----------------------------------
# Chart selection & locations
CHART_VERSION="" # e.g., "2.0.32" (empty = latest)
CHART_NAME="instana-agent"
HELM_REPO="https://agents.instana.io/helm"
OUT_DIR="./instana-offline-kit" # where the kit is generated

# Desired labeling used when rendering (no secrets needed for render)
CLUSTER_NAME="CLUSTER_NAME"
ZONE_NAME="ZONE_NAME"
RENDER_NAMESPACE="instana-agent"
DUMMY_AGENT_KEY="DUMMY"
DUMMY_ENDPOINT_HOST="dummy.instana.local"

# Which packaging method to build (oc-mirror | docker)
METHOD="oc-mirror"

# Container runtime preference for METHOD=docker (auto|docker|podman)
RUNTIME_PREF="auto"

# ---- Architecture control -----------------------------------------------------
# Target CPU architecture for images saved into the kit (must match OCP workers)
# Common values: amd64, arm64
PULL_ARCH="amd64"

# Required to pull agent image from containers.instana.io
INSTANA_AGENT_KEY=""

# ---- Save with skopeo (Method=docker only) -----------------------------------
# When true, use skopeo copy --override-arch to produce docker-archive tars.
SAVE_WITH_SKOPEO="false"

# oc-mirror settings (used when METHOD="oc-mirror")
ARCHIVE_SIZE="4Gi" # size hint for oc-mirror archive
echo_disable=""
MIRROR_SUBDIR="mirror" # dir under OUT_DIR for oc-mirror tars
IMAGESET_CONFIG_NAME="imageset-config.yaml" # name under OUT_DIR/metadata

# ---- Values template knobs (used when writing values-internal.template.yaml) --
VALUES_INTERNAL_REGISTRY="default-route-openshift-image-registry.apps.DOMAIN"
VALUES_AGENT_KEY="AGENT_KEY"
VALUES_ENDPOINT_HOST="ENDPOINT_HOST" # example "ingress-red-saas.instana.io"
VALUES_ENDPOINT_PORT="443"
VALUES_AGENT_IMAGE_TAG="latest"
VALUES_K8S_SENSOR_TAG="latest"
VALUES_OPERATOR_TAG="latest"
VALUES_CLUSTER_NAME="${CLUSTER_NAME}"
VALUES_ZONE_NAME="${ZONE_NAME}"

# ---- oc-mirror template knobs (where to write the archive on disk) -----------
IMAGESET_ARCHIVE_SIZE="${ARCHIVE_SIZE}"
IMAGESET_STORAGE_PATH="${OUT_DIR}/${MIRROR_SUBDIR}"

# ----------------------------- Helper templates -------------------------------
# 1) Helm values template for Method B (docker/podman)
VALUES_INTERNAL_TEMPLATE="$(cat <<YAML
# values-internal.template.yaml
# Used with Method B (docker/podman import) to point the chart at your internal registry.
agent:
  key: "${VALUES_AGENT_KEY}"
  endpointHost: "${VALUES_ENDPOINT_HOST}"
  endpointPort: ${VALUES_ENDPOINT_PORT}
  image:
    name: "${VALUES_INTERNAL_REGISTRY}/instana-agent/instana-agent"
    tag: "${VALUES_AGENT_IMAGE_TAG}"
k8s_sensor:
  image:
    name: "${VALUES_INTERNAL_REGISTRY}/instana-agent/k8sensor"
    tag: "${VALUES_K8S_SENSOR_TAG}"
controllerManager:
  image:
    name: "${VALUES_INTERNAL_REGISTRY}/instana-agent/instana-agent-operator"
    tag: "${VALUES_OPERATOR_TAG}"
cluster:
  name: "${VALUES_CLUSTER_NAME}"
zone:
  name: "${VALUES_ZONE_NAME}"
# OpenShift SCCs are granted outside Helm by the import script.
YAML
)"

# 2) oc-mirror ImageSetConfiguration header for Method A
IMAGESET_CONFIG_HEADER="$(cat <<YAML
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
archiveSize: ${IMAGESET_ARCHIVE_SIZE}
storageConfig:
  local:
    path: ${IMAGESET_STORAGE_PATH}
mirror:
  additionalImages:
YAML
)"

# --------------------------------- Utilities ----------------------------------
die() { echo "FATAL: $*" >&2; exit 1; }
log() { echo ">>> $*"; }
save_template() { # $1 var name, $2 path
  local var_name="$1" out_path="$2" content
  # shellcheck disable=SC2296
  content="${!var_name}"
  mkdir -p "$(dirname -- "$out_path")"
  printf '%s' "$content" > "$out_path"
}
discover_runtime() {
  local pref="$1"
  case "$pref" in
    docker) command -v docker >/dev/null 2>&1 && { echo docker; return; } ;;
    podman) command -v podman >/dev/null 2>&1 && { echo podman; return; } ;;
    auto)
      if command -v docker >/dev/null 2>&1; then echo docker; return; fi
      if command -v podman  >/dev/null 2>&1; then echo podman;  return; fi
      ;;
  esac
  die "No suitable container runtime found (docker/podman)."
}
verify_arch_from_tar() { # $1 tar path -> prints arch, returns 0 if detected
  local tar="$1" arch
  if command -v skopeo >/dev/null 2>&1; then
    arch=$(skopeo inspect docker-archive:"$tar" \
      | awk -F '"' '/"Architecture"/ {print $4; exit}' || true)
    if [ -n "$arch" ]; then echo "$arch"; return 0; fi
  fi
  echo ""; return 1
}
verify_arch_from_remote() { # $1 image ref -> prints arch
  local img="$1" arch
  if command -v skopeo >/dev/null 2>&1; then
    arch=$(skopeo inspect docker://"$img" \
      | awk -F '"' '/"Architecture"/ {print $4; exit}' || true)
    echo "$arch"; return 0
  fi
  echo ""; return 1
}

# ----------------------------- CLI overrides ----------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart-version) CHART_VERSION="$2"; shift 2;;
    --cluster-name)  CLUSTER_NAME="$2"; shift 2; VALUES_CLUSTER_NAME="$CLUSTER_NAME";;
    --zone-name)     ZONE_NAME="$2";   shift 2; VALUES_ZONE_NAME="$ZONE_NAME";;
    --method)        METHOD="$2";      shift 2;;
    --out-dir)       OUT_DIR="$2";     shift 2; IMAGESET_STORAGE_PATH="${OUT_DIR}/${MIRROR_SUBDIR}";;
    --runtime)       RUNTIME_PREF="$2"; shift 2;;
    --pull-arch)     PULL_ARCH="$2";   shift 2;;
    --save-with-skopeo) SAVE_WITH_SKOPEO="true"; shift 1;;
    --instana-agent-key) INSTANA_AGENT_KEY="$2"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: $0 [--chart-version <ver>] [--cluster-name <name>] [--zone-name <name>]
  [--method oc-mirror|docker] [--out-dir <dir>] [--runtime auto|docker|podman]
  [--pull-arch <amd64|arm64] [--save-with-skopeo]
  [--instana-agent-key <agentKey>]

Notes:
- --pull-arch forces the architecture variant to download and save in the kit.
  This prevents runtime "exec format error" on clusters of a different CPU arch.
- --save-with-skopeo uses 'skopeo copy --override-arch' to create docker-archive tars.
- --instana-agent-key enables authenticated pulls from containers.instana.io
  (user "_", password=<agentKey>), required for the Instana agent image.
  See: https://www.ibm.com/docs/en/instana-observability/1.0.300?topic=docker-installing-agent
EOF
      exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

# -------------------------------- Prep dirs -----------------------------------
mkdir -p "${OUT_DIR}"/{charts,manifests,images,metadata}

# -------------------------------- Pull chart ----------------------------------
echo ">>> Pulling Instana Agent Helm chart (${CHART_VERSION:-latest}) from ${HELM_REPO}"
if [[ -n "${CHART_VERSION}" ]]; then
  helm pull --repo "${HELM_REPO}" "${CHART_NAME}" \
    --version "${CHART_VERSION}" \
    --destination "${OUT_DIR}/charts"
  CHART_TGZ="${OUT_DIR}/charts/${CHART_NAME}-${CHART_VERSION}.tgz"
else
  helm pull --repo "${HELM_REPO}" "${CHART_NAME}" \
    --destination "${OUT_DIR}/charts"
  # Pick the first chart tgz we just pulled
  CHART_TGZ="$(ls -1 "${OUT_DIR}/charts/${CHART_NAME}-"*.tgz | head -n1)"
  [[ -f "${CHART_TGZ}" ]] || die "Chart archive not found under ${OUT_DIR}/charts"
  # Derive version from the basename (instana-agent-X.Y.Z.tgz -> X.Y.Z)
  CHART_BASENAME="$(basename -- "${CHART_TGZ}")"
  CHART_VERSION="${CHART_BASENAME#${CHART_NAME}-}"
  CHART_VERSION="${CHART_VERSION%.tgz}"
fi

[[ -f "${CHART_TGZ}" ]] || die "Chart archive not found: ${CHART_TGZ}"
echo ">>> Using chart: ${CHART_TGZ}"

# ----------------- Render chart to discover any inline image refs --------------
log "Rendering chart to discover images..."
RENDERED="${OUT_DIR}/manifests/${CHART_NAME}-${CHART_VERSION}.rendered.yaml"
helm template instana-agent "${CHART_TGZ}" \
  --namespace "${RENDER_NAMESPACE}" \
  --set agent.key="${DUMMY_AGENT_KEY}" \
  --set agent.endpointHost="${DUMMY_ENDPOINT_HOST}" \
  --set cluster.name="${CLUSTER_NAME}" \
  --set zone.name="${ZONE_NAME}" > "${RENDERED}"

# ------------------------ Extract image refs (inline) --------------------------
log "Extracting image references (inline in templates)..."
IMAGES_TXT="${OUT_DIR}/metadata/images.txt"
# Grep the 'image:' lines, take the second field, strip quotes, unique sort
grep -E '^[[:space:]]*image:[[:space:]]' "${RENDERED}" \
  | awk '{print $2}' \
  | sed 's/"//g; s/'"'"'//g' \
  | sort -u > "${IMAGES_TXT}"
log "Images discovered (inline):"; cat "${IMAGES_TXT}"

# -------------------------- Seed operator-managed images -----------------------
# Upstream defaults (override via environment if your source differs)
: "${UPSTREAM_OPERATOR_IMAGE:=icr.io/instana/instana-agent-operator}"
: "${UPSTREAM_AGENT_IMAGE:=containers.instana.io/instana/release/agent/static}"
: "${UPSTREAM_K8S_SENSOR_IMAGE:=icr.io/instana/k8sensor}"

OP_REF="${UPSTREAM_OPERATOR_IMAGE}:${VALUES_OPERATOR_TAG}"
AGENT_REF="${UPSTREAM_AGENT_IMAGE}:${VALUES_AGENT_IMAGE_TAG}"
K8S_REF="${UPSTREAM_K8S_SENSOR_IMAGE}:${VALUES_K8S_SENSOR_TAG}"

log "Seeding operator-managed images (if missing):"
SEED_OPERATOR=1
if grep -qE "^${UPSTREAM_OPERATOR_IMAGE}:" "${IMAGES_TXT}"; then
  SEED_OPERATOR=0
  log "Operator image already present in images.txt; will not seed ${UPSTREAM_OPERATOR_IMAGE} again"
fi

for ref in "${OP_REF}" "${AGENT_REF}" "${K8S_REF}"; do
  # Skip seeding operator if any tag for ${UPSTREAM_OPERATOR_IMAGE} already exists
  if [[ "${ref}" == "${OP_REF}" && ${SEED_OPERATOR} -eq 0 ]]; then
    echo "  ~ ${OP_REF} (operator base present; not seeding duplicate tag)"
    continue
  fi
  if ! grep -qxF "${ref}" "${IMAGES_TXT}"; then
    echo "  + ${ref}"
    echo "${ref}" >> "${IMAGES_TXT}"
  else
    echo "  = ${ref} (already present)"
  fi
done
sort -u -o "${IMAGES_TXT}" "${IMAGES_TXT}"
# De-duplicate operator tags: if both ":latest" and other tags exist for the same base, drop ":latest"
OP_BASE="${UPSTREAM_OPERATOR_IMAGE}"
if grep -qE "^${OP_BASE}:" "${IMAGES_TXT}"; then
  if grep -qE "^${OP_BASE}:latest$" "${IMAGES_TXT}"; then
    OTHER=$(grep -E "^${OP_BASE}:" "${IMAGES_TXT}" | grep -v ":latest$" || true)
    if [[ -n "${OTHER}" ]]; then
      tmpfile="${IMAGES_TXT}.tmp"
      grep -vE "^${OP_BASE}:latest$" "${IMAGES_TXT}" > "${tmpfile}" && mv "${tmpfile}" "${IMAGES_TXT}"
      log "Removed ${OP_BASE}:latest because a specific tag is already listed"
    fi
  fi
fi
log "Final image set:"; cat "${IMAGES_TXT}"

# ----------------- Write values template for internal registry -----------------
VALUES_PATH="${OUT_DIR}/values-internal.template.yaml"
save_template VALUES_INTERNAL_TEMPLATE "${VALUES_PATH}"
log "Wrote values template: ${VALUES_PATH}"

# ---------------- Package according to METHOD (oc-mirror | docker) -------------
case "${METHOD}" in
  oc-mirror)
    log "METHOD=oc-mirror selected"
    command -v oc >/dev/null 2>&1 || die "'oc' CLI is required"
    oc mirror --help >/dev/null 2>&1 || die "oc-mirror plugin (v2) is required"
    TARDIR="${IMAGESET_STORAGE_PATH}"; mkdir -p "${TARDIR}"
    IMGCFG="${OUT_DIR}/metadata/${IMAGESET_CONFIG_NAME}"
    save_template IMAGESET_CONFIG_HEADER "${IMGCFG}"
    while IFS= read -r img; do printf '  - name: %s\n' "$img" >> "${IMGCFG}"; done < "${IMAGES_TXT}"
    log "Creating disk archive with oc-mirror (no cluster access needed)"
    oc mirror --config "${IMGCFG}" "file://${TARDIR}" --v2
    log "DONE. Copy '${OUT_DIR}' into the air‑gapped site."
    ;;

  docker)
    log "METHOD=docker selected (save each image as docker-archive .tar)"
    MAPPING="${OUT_DIR}/metadata/mapping.csv"; : > "${MAPPING}"

    if [[ "${SAVE_WITH_SKOPEO}" == "true" ]]; then
      command -v skopeo >/dev/null 2>&1 || die "skopeo is required when --save-with-skopeo is set"
      log "Using skopeo copy --override-arch=${PULL_ARCH} to create tars"

      while read -r IMG; do
        SAFE_NAME="$(echo "${IMG}" | sed 's#/#_#g; s#:#_#g')"
        TAR_PATH="${OUT_DIR}/images/${SAFE_NAME}.tar"
        log "Copying ${IMG} -> ${TAR_PATH} (arch=${PULL_ARCH})"

        # Auth for containers.instana.io (agent)
        SRC_AUTH_ARGS=()
        if [[ "${IMG}" == containers.instana.io/* ]]; then
          if [[ -n "${INSTANA_AGENT_KEY}" ]]; then
            SRC_AUTH_ARGS+=(--src-creds _:${INSTANA_AGENT_KEY})
          elif [[ -n "${REGISTRY_AUTH_FILE}" && -f "${REGISTRY_AUTH_FILE}" ]]; then
            SRC_AUTH_ARGS+=(--src-authfile "${REGISTRY_AUTH_FILE}")
          elif [[ -n "${XDG_RUNTIME_DIR}" && -f "${XDG_RUNTIME_DIR}/containers/auth.json" ]]; then
            SRC_AUTH_ARGS+=(--src-authfile "${XDG_RUNTIME_DIR}/containers/auth.json")
          elif [[ -f "${HOME}/.docker/config.json" ]]; then
            SRC_AUTH_ARGS+=(--src-authfile "${HOME}/.docker/config.json")
          else
            log "WARNING: No credentials found for containers.instana.io; copy may fail (requires user '_' + agent key)."
          fi
        fi

        skopeo copy --override-arch "${PULL_ARCH}" \
          "${SRC_AUTH_ARGS[@]}" \
          docker://"${IMG}" \
          docker-archive:"${TAR_PATH}" >/dev/null

        ACTUAL_ARCH="$(verify_arch_from_tar "${TAR_PATH}")"
        if [[ -n "${ACTUAL_ARCH}" && "${ACTUAL_ARCH}" != "${PULL_ARCH}" ]]; then
          die "Saved tar arch '${ACTUAL_ARCH}' does not match required '${PULL_ARCH}' for ${IMG}"
        fi
        echo "${IMG},${SAFE_NAME}" >> "${MAPPING}"
      done < "${IMAGES_TXT}"

    else
      RUNTIME="$(discover_runtime "${RUNTIME_PREF}")"
      log "Using container runtime: ${RUNTIME} (podman/docker)"
      CIO_LOGGED_IN=0

      while read -r IMG; do
        SAFE_NAME="$(echo "${IMG}" | sed 's#/#_#g; s#:#_#g')"
        TAR_PATH="${OUT_DIR}/images/${SAFE_NAME}.tar"

        log "Pulling ${IMG} --arch ${PULL_ARCH}"
        # If pulling from containers.instana.io (agent), login once using the provided agent key
        if [[ "${IMG}" == containers.instana.io/* && ${CIO_LOGGED_IN} -eq 0 ]]; then
          if [[ -n "${INSTANA_AGENT_KEY}" ]]; then
            log "Logging into containers.instana.io with provided agent key"
            ${RUNTIME} login containers.instana.io -u _ -p "${INSTANA_AGENT_KEY}" || true
          else
            log "WARNING: No INSTANA_AGENT_KEY provided; attempting anonymous pull from containers.instana.io (will fail)."
          fi
          CIO_LOGGED_IN=1
        fi

        if [[ "${RUNTIME}" == "podman" ]]; then
          ${RUNTIME} pull --arch "${PULL_ARCH}" "${IMG}"
        else
          ${RUNTIME} pull --platform "linux/${PULL_ARCH}" "${IMG}"
        fi

        ACT_REMOTE="$(verify_arch_from_remote "${IMG}")"
        if [[ -n "${ACT_REMOTE}" && "${ACT_REMOTE}" != "${PULL_ARCH}" ]]; then
          die "Pulled remote arch '${ACT_REMOTE}' != required '${PULL_ARCH}' for ${IMG}"
        fi

        log "Saving ${IMG} -> ${TAR_PATH}"
        ${RUNTIME} save -o "${TAR_PATH}" "${IMG}"

        ACTUAL_ARCH="$(verify_arch_from_tar "${TAR_PATH}")"
        if [[ -n "${ACTUAL_ARCH}" && "${ACTUAL_ARCH}" != "${PULL_ARCH}" ]]; then
          die "Saved tar arch '${ACTUAL_ARCH}' does not match required '${PULL_ARCH}' for ${IMG}"
        fi
        echo "${IMG},${SAFE_NAME}" >> "${MAPPING}"
      done < "${IMAGES_TXT}"
    fi

    log "DONE. Copy '${OUT_DIR}' into the air‑gapped site."
    ;;

  *) die "Unknown METHOD='${METHOD}'. Use 'oc-mirror' or 'docker'.";;
esac