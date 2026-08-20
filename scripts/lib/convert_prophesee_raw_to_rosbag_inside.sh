#!/usr/bin/env bash
set -euo pipefail

source /opt/ros/noetic/setup.bash
source "${ROS_DEVEL_SPACE}/setup.bash"
source /workspace/scripts/lib/prophesee_common.sh

[ -f "${RAW_FILE}" ] || { echo "RAW file not found: ${RAW_FILE}" >&2; exit 1; }
if rosnode list >/dev/null 2>&1; then
  echo "A ROS master is already running. Stop live drivers before conversion." >&2
  exit 1
fi
raw_info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${RAW_FILE}")"
validate_raw_profile "${raw_info}" "${EXPECTED_WIDTH}" "${EXPECTED_HEIGHT}" "${EXPECTED_GENERATION_MAJOR}" "${EXPECTED_SYSTEM_IDS}"
serial="$(printf '%s\n' "${raw_info}" | kv_value serial)"
width="$(printf '%s\n' "${raw_info}" | kv_value width)"
height="$(printf '%s\n' "${raw_info}" | kv_value height)"
generation_major="$(printf '%s\n' "${raw_info}" | kv_value generation_major)"
system_id="$(printf '%s\n' "${raw_info}" | kv_value system_id)"
raw_event_count="$(printf '%s\n' "${raw_info}" | kv_value cd_event_count)"
raw_trigger_count="$(printf '%s\n' "${raw_info}" | kv_value trigger_event_count)"
first_timestamp_us="$(printf '%s\n' "${raw_info}" | kv_value first_timestamp_us)"
duration_us="$(printf '%s\n' "${raw_info}" | kv_value duration_us)"
[ "$((raw_event_count + raw_trigger_count))" -gt 0 ] || {
  echo "RAW contains neither CD events nor external trigger events." >&2
  exit 1
}

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
base="${BAG_PREFIX}_${serial}_${stamp}"
bag_file="${DATA_ROOT}/rosbag/${base}.bag"
manifest="${DATA_ROOT}/manifests/${base}.bag.yaml"
mkdir -p "${DATA_ROOT}/rosbag" "${DATA_ROOT}/manifests"

core_pid=""
bag_pid=""
publisher_pid=""
cleanup() {
  set +e
  for pid in "${publisher_pid}" "${bag_pid}" "${core_pid}"; do
    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
      kill -INT "${pid}" 2>/dev/null
      wait "${pid}" 2>/dev/null
    fi
  done
}
trap cleanup EXIT INT TERM

roscore >/tmp/prophesee_roscore.log 2>&1 &
core_pid=$!
for _ in $(seq 1 100); do rosnode list >/dev/null 2>&1 && break; sleep 0.1; done
rosnode list >/dev/null 2>&1

rosbag record -O "${bag_file}" /dvs/events /dvs/camera_info /dvs/ext_trigger \
  >/tmp/prophesee_rosbag.log 2>&1 &
bag_pid=$!
timestamp_offset_sec="$(python3 -c "import time; print(time.time() + float(${PLAYBACK_LEAD_SECONDS}))")"
watchdog_seconds="$(python3 -c "import math; print(math.ceil(${duration_us} / 1000000.0 + float(${PLAYBACK_LEAD_SECONDS})) + 10)")"
timeout --signal=INT --kill-after=5s "${watchdog_seconds}s" \
  rosrun event_camera_prophesee_tools prophesee_raw_dvs_publisher \
  __ns:=/dvs _raw_file_to_read:="${RAW_FILE}" _event_delta_t:="${EVENT_DELTA_T}" \
  _timestamp_offset_sec:="${timestamp_offset_sec}" _timestamp_base_us:="${first_timestamp_us}" \
  >/tmp/prophesee_raw_publisher.log 2>&1 &
publisher_pid=$!
for _ in $(seq 1 100); do
  rostopic info /dvs/events 2>/dev/null | grep -q '/record_' && break
  sleep 0.1
done
if ! rostopic info /dvs/events 2>/dev/null | grep -q '/record_'; then
  echo "rosbag did not subscribe to /dvs/events." >&2
  exit 1
fi

set +e
wait "${publisher_pid}"
publisher_status=$?
set -e
publisher_pid=""
if [ "${publisher_status}" -ne 0 ]; then
  echo "RAW publisher failed with status ${publisher_status}." >&2
  sed -n '1,160p' /tmp/prophesee_raw_publisher.log >&2
  exit 1
fi
sleep 0.5
kill -INT "${bag_pid}" 2>/dev/null || true
wait "${bag_pid}" || true
bag_pid=""

rosbag info "${bag_file}"
rosbag check "${bag_file}"
event_info="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /dvs/events)"
trigger_info="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /dvs/ext_trigger)"
bag_event_count="$(printf '%s\n' "${event_info}" | kv_value event_count)"
bag_trigger_count="$(printf '%s\n' "${trigger_info}" | kv_value event_count)"

comparison="$(python3 -c "er=${raw_event_count}; eb=${bag_event_count}; tr=${raw_trigger_count}; tb=${bag_trigger_count}; ed=abs(er-eb); td=abs(tr-tb); eratio=ed/er if er else (0 if ed==0 else 1); tratio=td/tr if tr else (0 if td==0 else 1); print(ed, td, eratio, tratio, max(eratio,tratio))")"
read -r event_difference trigger_difference event_difference_ratio trigger_difference_ratio difference_ratio <<<"${comparison}"
integrity_passed=false
if [ "${INTEGRITY_MODE}" = "strict" ]; then
  [ "${event_difference}" -eq 0 ] && [ "${trigger_difference}" -eq 0 ] && integrity_passed=true
else
  python3 -c "raise SystemExit(0 if ${difference_ratio} <= 0.001 else 1)" && integrity_passed=true
fi

python3 /workspace/scripts/lib/write_recording_manifest.py \
  --output "${manifest}" --field "data_kind=rosbag_from_raw" \
  --field "data_file=${bag_file}" --field "sha256=$(sha256sum "${bag_file}" | awk '{print $1}')" \
  --field "source_raw=${RAW_FILE}" --field "source_raw_sha256=$(sha256sum "${RAW_FILE}" | awk '{print $1}')" \
  --field "serial=${serial}" --field "width=${width}" --field "height=${height}" \
  --field "generation_major=${generation_major}" \
  --field "system_id=${system_id}" \
  --field "raw_event_count=${raw_event_count}" --field "bag_event_count=${bag_event_count}" \
  --field "raw_trigger_count=${raw_trigger_count}" --field "bag_trigger_count=${bag_trigger_count}" \
  --field "event_difference=${event_difference}" --field "trigger_difference=${trigger_difference}" \
  --field "event_difference_ratio=${event_difference_ratio}" \
  --field "trigger_difference_ratio=${trigger_difference_ratio}" \
  --field "difference_ratio=${difference_ratio}" --field "integrity_mode=${INTEGRITY_MODE}" \
  --field "integrity_passed=${integrity_passed}" --field "event_delta_t_s=${EVENT_DELTA_T}" \
  --field "timestamp_policy=shared_raw_origin" \
  --field "openeb_version=${OPENEB_VERSION}" --field "openeb_commit=${OPENEB_COMMIT}" \
  --field "project_commit=$(project_commit)" --field "project_dirty=$(project_dirty)" \
  --field "calibration_sha256=$(calibration_sha "${serial}")"

echo "Bag: ${bag_file}"
echo "Manifest: ${manifest}"
if [ "${integrity_passed}" != "true" ]; then
  echo "Integrity check failed in ${INTEGRITY_MODE} mode." >&2
  exit 2
fi
