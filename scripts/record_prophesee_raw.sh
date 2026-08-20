#!/usr/bin/env bash
set -euo pipefail

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4}"
source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"

DURATION="${DURATION:-60}"
RAW_PREFIX="${RAW_PREFIX:-${CAMERA_PROFILE}}"
CAMERA_SERIAL="${CAMERA_SERIAL:-}"
CAM0_SERIAL="${CAM0_SERIAL:-}"
CAM1_SERIAL="${CAM1_SERIAL:-}"
BIAS_FILE="${BIAS_FILE:-}"
CAM0_BIAS_FILE="${CAM0_BIAS_FILE:-}"
CAM1_BIAS_FILE="${CAM1_BIAS_FILE:-}"
SYNC_MODE="${SYNC_MODE:-standalone}"

case "${CAMERA_PROFILE}" in
  prophesee_evk1_vga*)
    DATA_ROOT="/workspace/data/prophesee/evk1_vga"
    EXPECTED_WIDTH=640
    EXPECTED_HEIGHT=480
    EXPECTED_GENERATION_MAJOR=3
    EXPECTED_SYSTEM_IDS=21,28
    WRAPPER_COMMIT=not_used
    ;;
  prophesee_evk4*)
    DATA_ROOT="/workspace/data/prophesee"
    EXPECTED_WIDTH=1280
    EXPECTED_HEIGHT=720
    EXPECTED_GENERATION_MAJOR=4
    EXPECTED_SYSTEM_IDS=49
    WRAPPER_COMMIT=8eba7cecd19f31585032188a5daa5908c848e2c4
    ;;
  *)
    echo "RAW recording is supported for Prophesee EVK1-VGA and EVK4 profiles." >&2
    exit 1
    ;;
esac

if [ "${INSIDE_CONTAINER:-0}" != "1" ]; then
  run_in_container_as_root env \
    INSIDE_CONTAINER=1 CAMERA_PROFILE="${CAMERA_PROFILE}" DURATION="${DURATION}" \
    RAW_PREFIX="${RAW_PREFIX}" CAMERA_SERIAL="${CAMERA_SERIAL}" \
    CAM0_SERIAL="${CAM0_SERIAL}" CAM1_SERIAL="${CAM1_SERIAL}" \
    BIAS_FILE="${BIAS_FILE}" CAM0_BIAS_FILE="${CAM0_BIAS_FILE}" \
    CAM1_BIAS_FILE="${CAM1_BIAS_FILE}" SYNC_MODE="${SYNC_MODE}" \
    DATA_ROOT="${DATA_ROOT}" EXPECTED_WIDTH="${EXPECTED_WIDTH}" \
    EXPECTED_HEIGHT="${EXPECTED_HEIGHT}" \
    EXPECTED_GENERATION_MAJOR="${EXPECTED_GENERATION_MAJOR}" \
    EXPECTED_SYSTEM_IDS="${EXPECTED_SYSTEM_IDS}" \
    WRAPPER_COMMIT="${WRAPPER_COMMIT}" \
    ROS_DEVEL_SPACE="${ROS_DEVEL_SPACE}" \
    bash /workspace/scripts/record_prophesee_raw.sh
  exit $?
fi

source /opt/ros/noetic/setup.bash
source "${ROS_DEVEL_SPACE}/setup.bash"
source /workspace/scripts/lib/prophesee_common.sh
require_safe_prefix "${RAW_PREFIX}"
mkdir -p "${DATA_ROOT}/raw" "${DATA_ROOT}/manifests"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ "${CAMERA_PROFILE}" == *_dual* ]]; then
  if [ -z "${CAM0_SERIAL}" ] || [ -z "${CAM1_SERIAL}" ] || [ "${CAM0_SERIAL}" = "${CAM1_SERIAL}" ]; then
    echo "Dual RAW recording requires distinct CAM0_SERIAL and CAM1_SERIAL." >&2
    exit 1
  fi
  case "${SYNC_MODE}" in
    standalone|master_slave) ;;
    *) echo "SYNC_MODE must be standalone or master_slave." >&2; exit 1 ;;
  esac
  base="${RAW_PREFIX}_pair_${stamp}"
  cam0_raw="${DATA_ROOT}/raw/${base}_cam0_${CAM0_SERIAL}.raw"
  cam1_raw="${DATA_ROOT}/raw/${base}_cam1_${CAM1_SERIAL}.raw"
  manifest="${DATA_ROOT}/manifests/${base}.raw_pair.yaml"
  recorder=(rosrun event_camera_prophesee_tools prophesee_dual_raw_recorder
    --cam0-serial "${CAM0_SERIAL}" --cam1-serial "${CAM1_SERIAL}"
    --cam0-output "${cam0_raw}" --cam1-output "${cam1_raw}"
    --duration "${DURATION}" --sync-mode "${SYNC_MODE}"
    --expected-width "${EXPECTED_WIDTH}" --expected-height "${EXPECTED_HEIGHT}"
    --expected-generation-major "${EXPECTED_GENERATION_MAJOR}")
  recorder+=(--expected-system-ids "${EXPECTED_SYSTEM_IDS}")
  [ -z "${CAM0_BIAS_FILE}" ] || recorder+=(--cam0-bias-file "${CAM0_BIAS_FILE}")
  [ -z "${CAM1_BIAS_FILE}" ] || recorder+=(--cam1-bias-file "${CAM1_BIAS_FILE}")
  "${recorder[@]}"

  info0="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${cam0_raw}")"
  info1="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${cam1_raw}")"
  cam0_bias_sidecar="${cam0_raw%.raw}.bias"
  cam1_bias_sidecar="${cam1_raw%.raw}.bias"
  cam0_settings_policy=openeb_defaults
  cam1_settings_policy=openeb_defaults
  [ -z "${CAM0_BIAS_FILE}" ] || cam0_settings_policy=openeb_defaults_with_bias_override
  [ -z "${CAM1_BIAS_FILE}" ] || cam1_settings_policy=openeb_defaults_with_bias_override
  python3 /workspace/scripts/lib/write_recording_manifest.py \
    --output "${manifest}" \
    --field "data_kind=openeb_raw_pair" \
    --field "cam0_file=${cam0_raw}" --field "cam1_file=${cam1_raw}" \
    --field "cam0_sha256=$(sha256sum "${cam0_raw}" | awk '{print $1}')" \
    --field "cam1_sha256=$(sha256sum "${cam1_raw}" | awk '{print $1}')" \
    --field "cam0_serial=${CAM0_SERIAL}" --field "cam1_serial=${CAM1_SERIAL}" \
    --field "cam0_event_count=$(printf '%s\n' "${info0}" | kv_value cd_event_count)" \
    --field "cam1_event_count=$(printf '%s\n' "${info1}" | kv_value cd_event_count)" \
    --field "cam0_trigger_count=$(printf '%s\n' "${info0}" | kv_value trigger_event_count)" \
    --field "cam1_trigger_count=$(printf '%s\n' "${info1}" | kv_value trigger_event_count)" \
    --field "cam0_encoding=$(printf '%s\n' "${info0}" | kv_value encoding)" \
    --field "cam1_encoding=$(printf '%s\n' "${info1}" | kv_value encoding)" \
    --field "cam0_firmware=$(printf '%s\n' "${info0}" | kv_value firmware)" \
    --field "cam1_firmware=$(printf '%s\n' "${info1}" | kv_value firmware)" \
    --field "cam0_camera_settings_policy=${cam0_settings_policy}" \
    --field "cam1_camera_settings_policy=${cam1_settings_policy}" \
    --field "width=${EXPECTED_WIDTH}" --field "height=${EXPECTED_HEIGHT}" \
    --field "generation_major=${EXPECTED_GENERATION_MAJOR}" \
    --field "cam0_system_id=$(printf '%s\n' "${info0}" | kv_value system_id)" \
    --field "cam1_system_id=$(printf '%s\n' "${info1}" | kv_value system_id)" \
    --field "sync_mode=${SYNC_MODE}" --field "sync_verified=false" \
    --field "requested_duration_s=${DURATION}" \
    --field "openeb_version=${OPENEB_VERSION}" --field "openeb_commit=${OPENEB_COMMIT}" \
    --field "wrapper_commit=${WRAPPER_COMMIT}" \
    --field "cam0_bias_file=${cam0_bias_sidecar}" \
    --field "cam1_bias_file=${cam1_bias_sidecar}" \
    --field "cam0_bias_sha256=$(file_sha_or_none "${cam0_bias_sidecar}")" \
    --field "cam1_bias_sha256=$(file_sha_or_none "${cam1_bias_sidecar}")" \
    --field "cam0_input_bias_sha256=$(file_sha_or_none "${CAM0_BIAS_FILE}")" \
    --field "cam1_input_bias_sha256=$(file_sha_or_none "${CAM1_BIAS_FILE}")" \
    --field "cam0_calibration_sha256=$(calibration_sha "${CAM0_SERIAL}")" \
    --field "cam1_calibration_sha256=$(calibration_sha "${CAM1_SERIAL}")" \
    --field "project_commit=$(project_commit)" --field "project_dirty=$(project_dirty)"
  echo "RAW pair: ${cam0_raw} ${cam1_raw}"
  echo "Manifest: ${manifest}"
  exit 0
fi

device_info="$(rosrun event_camera_prophesee_tools prophesee_device_info)"
serial="$(printf '%s\n' "${device_info}" | kv_value serial)"
device_firmware="$(printf '%s\n' "${device_info}" | kv_value firmware)"
if [ -n "${CAMERA_SERIAL}" ] && [ "${CAMERA_SERIAL}" != "${serial}" ]; then
  echo "CAMERA_SERIAL=${CAMERA_SERIAL} does not match detected camera ${serial}." >&2
  exit 1
fi
width="$(printf '%s\n' "${device_info}" | kv_value width)"
height="$(printf '%s\n' "${device_info}" | kv_value height)"
generation_major="$(printf '%s\n' "${device_info}" | kv_value generation_major)"
system_id="$(printf '%s\n' "${device_info}" | kv_value system_id)"
case ",${EXPECTED_SYSTEM_IDS}," in
  *,"${system_id}",*) ;;
  *)
    echo "Detected system_ID=${system_id} does not match ${CAMERA_PROFILE} (${EXPECTED_SYSTEM_IDS})." >&2
    exit 1
    ;;
esac
if [ "${width}" != "${EXPECTED_WIDTH}" ] || [ "${height}" != "${EXPECTED_HEIGHT}" ] ||
   [ "${generation_major}" != "${EXPECTED_GENERATION_MAJOR}" ]; then
  echo "Detected geometry ${width}x${height}, generation ${generation_major} does not match ${CAMERA_PROFILE}." >&2
  exit 1
fi
base="${RAW_PREFIX}_${serial}_${stamp}"
raw_file="${DATA_ROOT}/raw/${base}.raw"
manifest="${DATA_ROOT}/manifests/${base}.raw.yaml"
recorder=(rosrun event_camera_prophesee_tools prophesee_raw_recorder
  --output "${raw_file}" --duration "${DURATION}" --serial "${serial}")
[ -z "${BIAS_FILE}" ] || recorder+=(--bias-file "${BIAS_FILE}")
"${recorder[@]}"
raw_info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${raw_file}")"
bias_sidecar="${raw_file%.raw}.bias"
firmware="$(printf '%s\n' "${raw_info}" | kv_value firmware)"
firmware="${firmware:-${device_firmware}}"
camera_settings_policy=openeb_defaults
[ -z "${BIAS_FILE}" ] || camera_settings_policy=openeb_defaults_with_bias_override
python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" \
  --field "data_kind=openeb_raw" --field "data_file=${raw_file}" \
  --field "sha256=$(sha256sum "${raw_file}" | awk '{print $1}')" \
  --field "serial=${serial}" --field "width=${width}" --field "height=${height}" \
  --field "generation_major=${generation_major}" \
  --field "system_id=${system_id}" \
  --field "encoding=$(printf '%s\n' "${raw_info}" | kv_value encoding)" \
  --field "firmware=${firmware}" \
  --field "event_count=$(printf '%s\n' "${raw_info}" | kv_value cd_event_count)" \
  --field "trigger_count=$(printf '%s\n' "${raw_info}" | kv_value trigger_event_count)" \
  --field "camera_settings_policy=${camera_settings_policy}" \
  --field "bias_file=${bias_sidecar}" \
  --field "bias_sha256=$(file_sha_or_none "${bias_sidecar}")" \
  --field "input_bias_sha256=$(file_sha_or_none "${BIAS_FILE}")" \
  --field "requested_duration_s=${DURATION}" \
  --field "openeb_version=${OPENEB_VERSION}" --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "wrapper_commit=${WRAPPER_COMMIT}" \
  --field "project_commit=$(project_commit)" --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"
echo "RAW: ${raw_file}"
echo "Manifest: ${manifest}"
