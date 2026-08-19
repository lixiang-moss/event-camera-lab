#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

DURATION="${DURATION:-60}"
BAG_PREFIX="${BAG_PREFIX:-evk4_ros}"
EVENT_TOPIC="${EVENT_TOPIC:-/dvs/events}"
CAMERA_INFO_TOPIC="${CAMERA_INFO_TOPIC:-/dvs/camera_info}"
EVENT_DELTA_T="${EVENT_DELTA_T:-}"

if [ "${INSIDE_CONTAINER:-0}" != "1" ]; then
  run_in_container_as_root env \
    INSIDE_CONTAINER=1 \
    DURATION="${DURATION}" \
    BAG_PREFIX="${BAG_PREFIX}" \
    EVENT_TOPIC="${EVENT_TOPIC}" \
    CAMERA_INFO_TOPIC="${CAMERA_INFO_TOPIC}" \
    EVENT_DELTA_T="${EVENT_DELTA_T}" \
    bash /workspace/scripts/record_prophesee_rosbag.sh
  exit $?
fi

source /workspace/scripts/lib/prophesee_common.sh
require_safe_prefix "${BAG_PREFIX}"

datatype="$(rostopic type "${EVENT_TOPIC}" 2>/dev/null || true)"
if [ "${datatype}" != "dvs_msgs/EventArray" ]; then
  echo "${EVENT_TOPIC} must be dvs_msgs/EventArray; found '${datatype:-missing}'." >&2
  echo "Start prophesee_evk4 with enable_dvs_adapter:=true first." >&2
  exit 1
fi

serial="$(rosparam get /event_camera_driver/selected_serial 2>/dev/null | \
  python3 -c 'import sys, yaml; value = yaml.safe_load(sys.stdin.read()); print(value or "")' || true)"
if [ -z "${serial}" ] || [ "${serial}" = "unbound" ]; then
  echo "The running EVK4 profile does not expose a selected serial." >&2
  exit 1
fi
require_safe_prefix "${serial}"
actual_event_delta_t="$(rosparam get /event_camera_driver/event_delta_t 2>/dev/null | \
  python3 -c 'import sys, yaml; value = yaml.safe_load(sys.stdin.read()); print(value if value is not None else "")' || true)"
if [ -z "${actual_event_delta_t}" ]; then
  echo "The running EVK4 profile does not expose event_delta_t." >&2
  exit 1
fi
if [ -n "${EVENT_DELTA_T}" ]; then
  python3 -c 'import math, sys; raise SystemExit(0 if math.isclose(float(sys.argv[1]), float(sys.argv[2]), rel_tol=0.0, abs_tol=1e-12) else 1)' \
    "${EVENT_DELTA_T}" "${actual_event_delta_t}" || {
      echo "EVENT_DELTA_T=${EVENT_DELTA_T} does not match running driver value ${actual_event_delta_t}." >&2
      exit 1
    }
fi
EVENT_DELTA_T="${actual_event_delta_t}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
base="${BAG_PREFIX}_${serial}_${stamp}"
bag_file="/workspace/data/prophesee/rosbag/${base}.bag"
manifest="/workspace/data/prophesee/manifests/${base}.bag.yaml"
mkdir -p /workspace/data/prophesee/rosbag /workspace/data/prophesee/manifests

rosbag record --duration="${DURATION}" -O "${bag_file}" \
  "${EVENT_TOPIC}" "${CAMERA_INFO_TOPIC}"
rosbag info "${bag_file}"
rosbag check "${bag_file}"

bag_info="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic "${EVENT_TOPIC}")"
event_count="$(printf '%s\n' "${bag_info}" | kv_value event_count)"
message_count="$(printf '%s\n' "${bag_info}" | kv_value message_count)"
width="$(printf '%s\n' "${bag_info}" | kv_value width)"
height="$(printf '%s\n' "${bag_info}" | kv_value height)"
first_event_us="$(printf '%s\n' "${bag_info}" | kv_value first_event_us)"
last_event_us="$(printf '%s\n' "${bag_info}" | kv_value last_event_us)"
bag_sha="$(sha256sum "${bag_file}" | awk '{print $1}')"

python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" \
  --field "data_kind=rosbag_live" \
  --field "data_file=${bag_file}" \
  --field "sha256=${bag_sha}" \
  --field "serial=${serial}" \
  --field "event_topic=${EVENT_TOPIC}" \
  --field "event_type=dvs_msgs/EventArray" \
  --field "event_count=${event_count}" \
  --field "message_count=${message_count}" \
  --field "width=${width}" \
  --field "height=${height}" \
  --field "first_event_us=${first_event_us}" \
  --field "last_event_us=${last_event_us}" \
  --field "event_delta_t_s=${EVENT_DELTA_T}" \
  --field "timestamp_policy=ros_start_offset" \
  --field "requested_duration_s=${DURATION}" \
  --field "openeb_version=${OPENEB_VERSION}" \
  --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "wrapper_commit=8eba7cecd19f31585032188a5daa5908c848e2c4" \
  --field "project_commit=$(project_commit)" \
  --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"

echo "Bag: ${bag_file}"
echo "Manifest: ${manifest}"
