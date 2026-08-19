#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/prophesee_common.sh"

RAW_PREFIX="${RAW_PREFIX:-evk4_viewer}"
CAMERA_SETTINGS="${CAMERA_SETTINGS:-}"

if [ "${INSIDE_CONTAINER:-0}" != "1" ]; then
  container_camera_settings=""
  if [ -n "${CAMERA_SETTINGS}" ]; then
    container_camera_settings="$(to_container_path "${CAMERA_SETTINGS}")"
  fi
  run_in_container_as_root env \
    INSIDE_CONTAINER=1 \
    RAW_PREFIX="${RAW_PREFIX}" \
    CAMERA_SETTINGS="${container_camera_settings}" \
    bash /workspace/scripts/record_prophesee_raw_with_viewer.sh
  exit $?
fi

source /workspace/scripts/lib/prophesee_common.sh
require_safe_prefix "${RAW_PREFIX}"

device_info="$(rosrun event_camera_prophesee_tools prophesee_device_info)"
serial="$(printf '%s\n' "${device_info}" | kv_value serial)"
device_firmware="$(printf '%s\n' "${device_info}" | kv_value firmware)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
base="${RAW_PREFIX}_${serial}_${stamp}"
raw_file="/workspace/data/prophesee/raw/${base}.raw"
manifest="/workspace/data/prophesee/manifests/${base}.raw.yaml"
saved_settings="/workspace/data/prophesee/manifests/${base}.camera-settings.json"

mkdir -p /workspace/data/prophesee/raw /workspace/data/prophesee/manifests
viewer_args=(-o "${raw_file}" --output-camera-config "${saved_settings}")
input_settings_sha="none"
if [ -n "${CAMERA_SETTINGS}" ]; then
  if [ ! -f "${CAMERA_SETTINGS}" ]; then
    echo "Camera settings file not found: ${CAMERA_SETTINGS}" >&2
    exit 1
  fi
  viewer_args+=(--input-camera-config "${CAMERA_SETTINGS}")
  input_settings_sha="$(sha256sum "${CAMERA_SETTINGS}" | awk '{print $1}')"
fi
echo "Press Space to start/stop RAW recording. Press s to save actual camera settings, then q to close."
metavision_viewer "${viewer_args[@]}"

if [ ! -s "${raw_file}" ]; then
  echo "Viewer closed without creating a RAW recording." >&2
  exit 1
fi

raw_info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${raw_file}")"
event_count="$(printf '%s\n' "${raw_info}" | kv_value cd_event_count)"
width="$(printf '%s\n' "${raw_info}" | kv_value width)"
height="$(printf '%s\n' "${raw_info}" | kv_value height)"
encoding="$(printf '%s\n' "${raw_info}" | kv_value encoding)"
firmware="$(printf '%s\n' "${raw_info}" | kv_value firmware)"
firmware="${firmware:-${device_firmware}}"
raw_sha="$(sha256sum "${raw_file}" | awk '{print $1}')"
saved_settings_sha="none"
if [ -s "${saved_settings}" ]; then
  saved_settings_sha="$(sha256sum "${saved_settings}" | awk '{print $1}')"
fi
python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" \
  --field "data_kind=openeb_raw" \
  --field "recording_interface=metavision_viewer" \
  --field "data_file=${raw_file}" \
  --field "sha256=${raw_sha}" \
  --field "serial=${serial}" \
  --field "width=${width}" \
  --field "height=${height}" \
  --field "encoding=${encoding}" \
  --field "firmware=${firmware}" \
  --field "event_count=${event_count}" \
  --field "input_camera_settings=${CAMERA_SETTINGS:-none}" \
  --field "input_camera_settings_sha256=${input_settings_sha}" \
  --field "saved_camera_settings=${saved_settings}" \
  --field "saved_camera_settings_sha256=${saved_settings_sha}" \
  --field "openeb_version=${OPENEB_VERSION}" \
  --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "wrapper_commit=8eba7cecd19f31585032188a5daa5908c848e2c4" \
  --field "project_commit=$(project_commit)" \
  --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"

echo "RAW: ${raw_file}"
echo "Manifest: ${manifest}"
