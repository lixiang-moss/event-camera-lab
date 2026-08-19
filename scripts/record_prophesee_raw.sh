#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

DURATION="${DURATION:-60}"
RAW_PREFIX="${RAW_PREFIX:-evk4}"

if [ "${INSIDE_CONTAINER:-0}" != "1" ]; then
  run_in_container_as_root env \
    INSIDE_CONTAINER=1 \
    DURATION="${DURATION}" \
    RAW_PREFIX="${RAW_PREFIX}" \
    bash /workspace/scripts/record_prophesee_raw.sh
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

mkdir -p /workspace/data/prophesee/raw /workspace/data/prophesee/manifests
rosrun event_camera_prophesee_tools prophesee_raw_recorder \
  --output "${raw_file}" --duration "${DURATION}"

raw_info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${raw_file}")"
event_count="$(printf '%s\n' "${raw_info}" | kv_value cd_event_count)"
width="$(printf '%s\n' "${raw_info}" | kv_value width)"
height="$(printf '%s\n' "${raw_info}" | kv_value height)"
firmware="$(printf '%s\n' "${raw_info}" | kv_value firmware)"
firmware="${firmware:-${device_firmware}}"
encoding="$(printf '%s\n' "${raw_info}" | kv_value encoding)"
raw_sha="$(sha256sum "${raw_file}" | awk '{print $1}')"

python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" \
  --field "data_kind=openeb_raw" \
  --field "data_file=${raw_file}" \
  --field "sha256=${raw_sha}" \
  --field "serial=${serial}" \
  --field "width=${width}" \
  --field "height=${height}" \
  --field "encoding=${encoding}" \
  --field "firmware=${firmware}" \
  --field "event_count=${event_count}" \
  --field "camera_settings_policy=openeb_defaults" \
  --field "requested_duration_s=${DURATION}" \
  --field "openeb_version=${OPENEB_VERSION}" \
  --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "wrapper_commit=8eba7cecd19f31585032188a5daa5908c848e2c4" \
  --field "project_commit=$(project_commit)" \
  --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"

echo "RAW: ${raw_file}"
echo "Manifest: ${manifest}"
