#!/usr/bin/env bash
set -euo pipefail

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4}"
source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"

DURATION="${DURATION:-60}"
BAG_PREFIX="${BAG_PREFIX:-${CAMERA_PROFILE}}"
EXPECTED_EVENT_DELTA_T="${EXPECTED_EVENT_DELTA_T:-${EVENT_DELTA_T:-}}"
EXPECTED_SYNC_MODE="${EXPECTED_SYNC_MODE:-${SYNC_MODE:-}}"

case "${CAMERA_PROFILE}" in
  prophesee_evk1_vga*)
    DATA_ROOT="/workspace/data/prophesee/evk1_vga"
    WRAPPER_COMMIT=not_used
    ;;
  prophesee_evk4*)
    DATA_ROOT="/workspace/data/prophesee"
    WRAPPER_COMMIT=8eba7cecd19f31585032188a5daa5908c848e2c4
    ;;
  *)
    echo "Use record_events.sh for non-Prophesee profiles." >&2
    exit 1
    ;;
esac

if [ "${INSIDE_CONTAINER:-0}" != "1" ]; then
  run_in_container_as_root env \
    INSIDE_CONTAINER=1 CAMERA_PROFILE="${CAMERA_PROFILE}" DURATION="${DURATION}" \
    BAG_PREFIX="${BAG_PREFIX}" \
    EXPECTED_EVENT_DELTA_T="${EXPECTED_EVENT_DELTA_T}" \
    EXPECTED_SYNC_MODE="${EXPECTED_SYNC_MODE}" \
    DATA_ROOT="${DATA_ROOT}" WRAPPER_COMMIT="${WRAPPER_COMMIT}" \
    ROS_DEVEL_SPACE="${ROS_DEVEL_SPACE}" \
    bash /workspace/scripts/record_prophesee_rosbag.sh
  exit $?
fi

source /opt/ros/noetic/setup.bash
source "${ROS_DEVEL_SPACE}/setup.bash"
source /workspace/scripts/lib/prophesee_common.sh
require_safe_prefix "${BAG_PREFIX}"
mkdir -p "${DATA_ROOT}/rosbag" "${DATA_ROOT}/manifests"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

rosparam_value() {
  local key="$1"
  local value
  value="$(rosparam get "${key}" 2>/dev/null || true)"
  value="${value//\'/}"
  printf '%s\n' "${value}"
}

first_rosparam_value() {
  local key value
  for key in "$@"; do
    value="$(rosparam_value "${key}")"
    if [ -n "${value}" ]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done
  return 1
}

assert_float_match() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [ -z "${expected}" ] || python3 -c \
    "import math; raise SystemExit(0 if math.isclose(float('${expected}'), float('${actual}'), rel_tol=1e-9, abs_tol=1e-12) else 1)" || {
      echo "${label} expected ${expected}, but running driver uses ${actual}." >&2
      exit 1
    }
}

if [[ "${CAMERA_PROFILE}" == *_dual* ]]; then
  topics=(/cam0/events /cam0/camera_info /cam0/ext_trigger
          /cam1/events /cam1/camera_info /cam1/ext_trigger)
  for topic in /cam0/events /cam1/events; do
    datatype="$(rostopic type "${topic}" 2>/dev/null || true)"
    if [ "${datatype}" != "dvs_msgs/EventArray" ]; then
      echo "${topic} must be dvs_msgs/EventArray; found '${datatype:-missing}'." >&2
      exit 1
    fi
  done
  serial0="$(rosparam get /cam0/event_camera_driver/selected_serial 2>/dev/null || true)"
  serial1="$(rosparam get /cam1/event_camera_driver/selected_serial 2>/dev/null || true)"
  serial0="${serial0//\'/}"
  serial1="${serial1//\'/}"
  [ -n "${serial0}" ] && [ -n "${serial1}" ] && [ "${serial0}" != "${serial1}" ] || {
    echo "Dual Prophesee driver serial parameters are missing or identical." >&2
    exit 1
  }
  event_delta0="$(rosparam_value /cam0/event_camera_driver/event_delta_t)"
  event_delta1="$(rosparam_value /cam1/event_camera_driver/event_delta_t)"
  [ -n "${event_delta0}" ] && [ -n "${event_delta1}" ] || {
    echo "Dual driver event_delta_t parameters are missing." >&2
    exit 1
  }
  assert_float_match "${event_delta0}" "${event_delta1}" "cam1 event_delta_t"
  assert_float_match "${EXPECTED_EVENT_DELTA_T}" "${event_delta0}" "event_delta_t"
  sync0="$(rosparam_value /cam0/event_camera_driver/sync_mode)"
  sync1="$(rosparam_value /cam1/event_camera_driver/sync_mode)"
  if [ "${sync0}" = master ] && [ "${sync1}" = slave ]; then
    actual_sync_mode=master_slave
  elif [ "${sync0}" = standalone ] && [ "${sync1}" = standalone ]; then
    actual_sync_mode=standalone
  else
    echo "Unexpected dual synchronization roles: cam0=${sync0:-missing}, cam1=${sync1:-missing}." >&2
    exit 1
  fi
  if [ -n "${EXPECTED_SYNC_MODE}" ] && [ "${EXPECTED_SYNC_MODE}" != "${actual_sync_mode}" ]; then
    echo "SYNC_MODE expected ${EXPECTED_SYNC_MODE}, but running drivers use ${actual_sync_mode}." >&2
    exit 1
  fi
  cam0_bias_file="$(rosparam_value /cam0/event_camera_driver/bias_file)"
  cam1_bias_file="$(rosparam_value /cam1/event_camera_driver/bias_file)"
  base="${BAG_PREFIX}_pair_${stamp}"
  bag_file="${DATA_ROOT}/rosbag/${base}.bag"
  manifest="${DATA_ROOT}/manifests/${base}.bag_pair.yaml"
  rosbag record --duration="${DURATION}" -O "${bag_file}" "${topics[@]}"
  rosbag info "${bag_file}"
  rosbag check "${bag_file}"
  info0="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam0/events)"
  info1="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam1/events)"
  trig0="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam0/ext_trigger)"
  trig1="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam1/ext_trigger)"
  python3 /workspace/scripts/lib/write_recording_manifest.py \
    --output "${manifest}" --field "data_kind=rosbag_live_pair" \
    --field "data_file=${bag_file}" --field "sha256=$(sha256sum "${bag_file}" | awk '{print $1}')" \
    --field "cam0_serial=${serial0}" --field "cam1_serial=${serial1}" \
    --field "cam0_event_count=$(printf '%s\n' "${info0}" | kv_value event_count)" \
    --field "cam1_event_count=$(printf '%s\n' "${info1}" | kv_value event_count)" \
    --field "cam0_trigger_count=$(printf '%s\n' "${trig0}" | kv_value event_count)" \
    --field "cam1_trigger_count=$(printf '%s\n' "${trig1}" | kv_value event_count)" \
    --field "event_delta_t_s=${event_delta0}" --field "requested_duration_s=${DURATION}" \
    --field "sync_mode=${actual_sync_mode}" --field "sync_verified=false" \
    --field "cam0_bias_file=${cam0_bias_file:-none}" \
    --field "cam1_bias_file=${cam1_bias_file:-none}" \
    --field "cam0_bias_sha256=$(file_sha_or_none "${cam0_bias_file}")" \
    --field "cam1_bias_sha256=$(file_sha_or_none "${cam1_bias_file}")" \
    --field "cam0_calibration_sha256=$(calibration_sha "${serial0}")" \
    --field "cam1_calibration_sha256=$(calibration_sha "${serial1}")" \
    --field "openeb_version=${OPENEB_VERSION}" \
    --field "openeb_commit=${OPENEB_COMMIT}" --field "wrapper_commit=${WRAPPER_COMMIT}" \
    --field "project_commit=$(project_commit)" --field "project_dirty=$(project_dirty)"
  echo "Bag: ${bag_file}"
  echo "Manifest: ${manifest}"
  exit 0
fi

EVENT_TOPIC="${EVENT_TOPIC:-/dvs/events}"
CAMERA_INFO_TOPIC="${CAMERA_INFO_TOPIC:-/dvs/camera_info}"
TRIGGER_TOPIC="${TRIGGER_TOPIC:-/dvs/ext_trigger}"
datatype="$(rostopic type "${EVENT_TOPIC}" 2>/dev/null || true)"
if [ "${datatype}" != "dvs_msgs/EventArray" ]; then
  echo "${EVENT_TOPIC} must be dvs_msgs/EventArray; found '${datatype:-missing}'." >&2
  exit 1
fi
serial="$(rosparam get /dvs/event_camera_driver/selected_serial 2>/dev/null || \
          rosparam get /event_camera_driver/selected_serial 2>/dev/null || true)"
serial="${serial//\'/}"
[ -n "${serial}" ] || { echo "The running profile does not expose a selected serial." >&2; exit 1; }
actual_event_delta_t="$(first_rosparam_value \
  /dvs/event_camera_driver/event_delta_t \
  /event_camera_driver/event_delta_t || true)"
[ -n "${actual_event_delta_t}" ] || {
  echo "The running profile does not expose event_delta_t." >&2
  exit 1
}
assert_float_match "${EXPECTED_EVENT_DELTA_T}" "${actual_event_delta_t}" "event_delta_t"
actual_sync_mode="$(first_rosparam_value \
  /dvs/event_camera_driver/sync_mode \
  /event_camera_driver/sync_mode || true)"
actual_sync_mode="${actual_sync_mode:-not_exposed}"
if [ -n "${EXPECTED_SYNC_MODE}" ] && [ "${EXPECTED_SYNC_MODE}" != "${actual_sync_mode}" ]; then
  echo "SYNC_MODE expected ${EXPECTED_SYNC_MODE}, but running driver reports ${actual_sync_mode}." >&2
  exit 1
fi
bias_file="$(first_rosparam_value \
  /dvs/event_camera_driver/bias_file \
  /event_camera_driver/bias_file || true)"
base="${BAG_PREFIX}_${serial}_${stamp}"
bag_file="${DATA_ROOT}/rosbag/${base}.bag"
manifest="${DATA_ROOT}/manifests/${base}.bag.yaml"
topics=("${EVENT_TOPIC}" "${CAMERA_INFO_TOPIC}")
[ -n "$(rostopic type "${TRIGGER_TOPIC}" 2>/dev/null || true)" ] && topics+=("${TRIGGER_TOPIC}")
rosbag record --duration="${DURATION}" -O "${bag_file}" "${topics[@]}"
rosbag info "${bag_file}"
rosbag check "${bag_file}"
bag_info="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic "${EVENT_TOPIC}")"
trigger_info="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic "${TRIGGER_TOPIC}")"
python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" --field "data_kind=rosbag_live" \
  --field "data_file=${bag_file}" --field "sha256=$(sha256sum "${bag_file}" | awk '{print $1}')" \
  --field "serial=${serial}" --field "event_topic=${EVENT_TOPIC}" \
  --field "event_count=$(printf '%s\n' "${bag_info}" | kv_value event_count)" \
  --field "message_count=$(printf '%s\n' "${bag_info}" | kv_value message_count)" \
  --field "trigger_count=$(printf '%s\n' "${trigger_info}" | kv_value event_count)" \
  --field "event_delta_t_s=${actual_event_delta_t}" --field "requested_duration_s=${DURATION}" \
  --field "sync_mode=${actual_sync_mode}" \
  --field "bias_file=${bias_file:-none}" \
  --field "bias_sha256=$(file_sha_or_none "${bias_file}")" \
  --field "openeb_version=${OPENEB_VERSION}" --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "wrapper_commit=${WRAPPER_COMMIT}" \
  --field "project_commit=$(project_commit)" --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"
echo "Bag: ${bag_file}"
echo "Manifest: ${manifest}"
