#!/usr/bin/env bash
set -euo pipefail

source /opt/ros/noetic/setup.bash
source /workspace/ros_ws/devel/setup.bash
source /workspace/scripts/lib/prophesee_common.sh

if [ ! -f "${RAW_FILE}" ]; then
  echo "RAW file not found: ${RAW_FILE}" >&2
  exit 1
fi
if rosnode list >/dev/null 2>&1; then
  echo "A ROS master is already running. Stop live drivers before conversion." >&2
  exit 1
fi

raw_info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${RAW_FILE}")"
serial="$(printf '%s\n' "${raw_info}" | kv_value serial)"
width="$(printf '%s\n' "${raw_info}" | kv_value width)"
height="$(printf '%s\n' "${raw_info}" | kv_value height)"
raw_event_count="$(printf '%s\n' "${raw_info}" | kv_value cd_event_count)"
duration_us="$(printf '%s\n' "${raw_info}" | kv_value duration_us)"
if [ "${raw_event_count}" -le 0 ]; then
  echo "RAW contains no CD events." >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
base="${BAG_PREFIX}_${serial}_${stamp}"
bag_file="/workspace/data/prophesee/rosbag/${base}.bag"
manifest="/workspace/data/prophesee/manifests/${base}.bag.yaml"
camera_info_url="file:///workspace/config/camera_info/prophesee_${serial}.yaml"
mkdir -p /workspace/data/prophesee/rosbag /workspace/data/prophesee/manifests

core_pid=""
adapter_pid=""
bag_pid=""
publisher_pid=""
cleanup() {
  set +e
  for pid in "${publisher_pid}" "${bag_pid}" "${adapter_pid}" "${core_pid}"; do
    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
      kill -INT "${pid}" 2>/dev/null
      wait "${pid}" 2>/dev/null
    fi
  done
}
trap cleanup EXIT INT TERM

roscore >/tmp/evk4_roscore.log 2>&1 &
core_pid=$!
for _ in $(seq 1 100); do
  rosnode list >/dev/null 2>&1 && break
  sleep 0.1
done
rosnode list >/dev/null 2>&1

rosrun event_camera_prophesee_tools prophesee_event_adapter \
  __ns:=/dvs \
  _source_events_topic:=/prophesee/camera/cd_events_buffer \
  _source_camera_info_topic:=/prophesee/camera/camera_info \
  _frame_id:=event_camera_optical_frame \
  _camera_name:="prophesee_${serial}" \
  _camera_info_url:="${camera_info_url}" \
  >/tmp/evk4_adapter.log 2>&1 &
adapter_pid=$!

for _ in $(seq 1 100); do
  rostopic info /dvs/events 2>/dev/null | grep -q 'Publishers:' && break
  sleep 0.1
done

rosbag record -O "${bag_file}" /dvs/events /dvs/camera_info \
  >/tmp/evk4_rosbag.log 2>&1 &
bag_pid=$!
for _ in $(seq 1 100); do
  rostopic info /dvs/events 2>/dev/null | grep -q '/record_' && break
  sleep 0.1
done
if ! rostopic info /dvs/events 2>/dev/null | grep -q '/record_'; then
  echo "rosbag did not subscribe to /dvs/events." >&2
  exit 1
fi

watchdog_seconds="$(python3 -c "import math; print(math.ceil(${duration_us} / 1000000.0) + 10)")"
timeout --signal=INT --kill-after=5s "${watchdog_seconds}s" \
  rosrun event_camera_prophesee_tools prophesee_raw_publisher \
  _camera_name:=camera \
  _frame_id:=event_camera_optical_frame \
  _raw_file_to_read:="${RAW_FILE}" \
  _event_delta_t:="${EVENT_DELTA_T}" \
  >/tmp/evk4_raw_publisher.log 2>&1 &
publisher_pid=$!

set +e
wait "${publisher_pid}"
publisher_status=$?
set -e
publisher_pid=""
if [ "${publisher_status}" -eq 124 ]; then
  echo "RAW publisher exceeded ${watchdog_seconds}s watchdog." >&2
  exit 1
fi
if [ "${publisher_status}" -ne 0 ]; then
  echo "RAW publisher failed with status ${publisher_status}." >&2
  sed -n '1,160p' /tmp/evk4_raw_publisher.log >&2
  exit 1
fi
sleep 1
kill -INT "${bag_pid}" 2>/dev/null || true
wait "${bag_pid}" || true
bag_pid=""

rosbag info "${bag_file}"
rosbag check "${bag_file}"
bag_info="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /dvs/events)"
bag_event_count="$(printf '%s\n' "${bag_info}" | kv_value event_count)"
message_count="$(printf '%s\n' "${bag_info}" | kv_value message_count)"
bag_first_event_us="$(printf '%s\n' "${bag_info}" | kv_value first_event_us)"
bag_last_event_us="$(printf '%s\n' "${bag_info}" | kv_value last_event_us)"
bag_event_duration_s="$(printf '%s\n' "${bag_info}" | kv_value event_duration_s)"

comparison="$(python3 -c "raw=${raw_event_count}; bag=${bag_event_count}; diff=abs(raw-bag); print(f'{diff} {diff/raw:.12f}')")"
read -r event_difference loss_ratio <<<"${comparison}"
integrity_passed=false
if [ "${INTEGRITY_MODE}" = "strict" ]; then
  [ "${event_difference}" -eq 0 ] && integrity_passed=true
else
  python3 -c "raise SystemExit(0 if ${loss_ratio} <= 0.001 else 1)" && integrity_passed=true
fi

raw_sha="$(sha256sum "${RAW_FILE}" | awk '{print $1}')"
bag_sha="$(sha256sum "${bag_file}" | awk '{print $1}')"
python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" \
  --field "data_kind=rosbag_from_raw" \
  --field "data_file=${bag_file}" \
  --field "sha256=${bag_sha}" \
  --field "source_raw=${RAW_FILE}" \
  --field "source_raw_sha256=${raw_sha}" \
  --field "serial=${serial}" \
  --field "width=${width}" \
  --field "height=${height}" \
  --field "event_topic=/dvs/events" \
  --field "event_type=dvs_msgs/EventArray" \
  --field "raw_event_count=${raw_event_count}" \
  --field "bag_event_count=${bag_event_count}" \
  --field "message_count=${message_count}" \
  --field "bag_first_event_us=${bag_first_event_us}" \
  --field "bag_last_event_us=${bag_last_event_us}" \
  --field "bag_event_duration_s=${bag_event_duration_s}" \
  --field "event_difference=${event_difference}" \
  --field "difference_ratio=${loss_ratio}" \
  --field "integrity_mode=${INTEGRITY_MODE}" \
  --field "integrity_passed=${integrity_passed}" \
  --field "event_delta_t_s=${EVENT_DELTA_T}" \
  --field "playback_rate=1.0" \
  --field "timestamp_policy=ros_start_offset" \
  --field "openeb_version=${OPENEB_VERSION}" \
  --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "wrapper_commit=8eba7cecd19f31585032188a5daa5908c848e2c4" \
  --field "project_commit=$(project_commit)" \
  --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"

echo "Bag: ${bag_file}"
echo "Manifest: ${manifest}"
echo "RAW events: ${raw_event_count}; bag events: ${bag_event_count}; difference: ${event_difference}"
if [ "${integrity_passed}" != "true" ]; then
  echo "Integrity check failed in ${INTEGRITY_MODE} mode." >&2
  exit 2
fi
