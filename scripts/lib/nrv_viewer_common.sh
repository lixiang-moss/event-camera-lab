#!/usr/bin/env bash

set -euo pipefail

NRV_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NRV_COMPOSE_FILE="${NRV_PROJECT_ROOT}/docker-compose.nrv.yml"
NRV_SERVICE_NAME="event-camera-nrv-viewer"
NRV_IMAGE_NAME="event-camera-lab:nrv-viewer-jammy"
NRV_VIEWER_SOURCE="${NRV_PROJECT_ROOT}/third_party/nrv/DVS_Viewer"
NRV_VIEWER_COMMIT="460512cec02255a627a3baa2737d9a496345d8fc"

nrv_compose() {
  docker compose -f "${NRV_COMPOSE_FILE}" "$@"
}

prepare_nrv_data_directories() {
  mkdir -p \
    "${NRV_PROJECT_ROOT}/data/nrv_delta/raw" \
    "${NRV_PROJECT_ROOT}/data/nrv_delta/hdf5" \
    "${NRV_PROJECT_ROOT}/data/nrv_delta/media" \
    "${NRV_PROJECT_ROOT}/data/nrv_delta/calibration"
}

check_nrv_viewer_source() {
  local actual_commit source_changes
  local required_files=(
    "Linux/x64/DVS_Viewer"
    "Linux/x64/libDELTA_SDK.so"
    "Linux/x64/libcyusb.so"
    "Linux/x64/settings/Delta_10_2000FPS.txt"
    "Linux/x64/calibration/settings/application/app_defaults.yaml"
  )
  local relative_path

  if [ ! -d "${NRV_VIEWER_SOURCE}/.git" ]; then
    cat >&2 <<EOF
NRV Viewer source is missing or is not a Git checkout:
  ${NRV_VIEWER_SOURCE}

Prepare the pinned upstream source with:
  git clone https://github.com/nrvcorp/DVS_Viewer.git ${NRV_VIEWER_SOURCE}
  git -C ${NRV_VIEWER_SOURCE} checkout ${NRV_VIEWER_COMMIT}
EOF
    return 1
  fi

  actual_commit="$(git -C "${NRV_VIEWER_SOURCE}" rev-parse HEAD)"
  if [ "${actual_commit}" != "${NRV_VIEWER_COMMIT}" ]; then
    echo "NRV Viewer commit mismatch." >&2
    echo "Expected: ${NRV_VIEWER_COMMIT}" >&2
    echo "Actual:   ${actual_commit}" >&2
    return 1
  fi

  source_changes="$(git -C "${NRV_VIEWER_SOURCE}" status --porcelain -- Linux/x64)"
  if [ -n "${source_changes}" ]; then
    echo "NRV Viewer Linux/x64 differs from the pinned upstream commit." >&2
    printf '%s\n' "${source_changes}" >&2
    return 1
  fi

  for relative_path in "${required_files[@]}"; do
    if [ ! -f "${NRV_VIEWER_SOURCE}/${relative_path}" ]; then
      echo "Missing required NRV Viewer file: ${relative_path}" >&2
      return 1
    fi
  done
}
