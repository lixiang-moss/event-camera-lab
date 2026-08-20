#!/usr/bin/env bash
set -euo pipefail

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4_dual}"
source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"
source "$(dirname "$0")/lib/prophesee_common.sh"

CAM0_RAW_FILE="${CAM0_RAW_FILE:-}"
CAM1_RAW_FILE="${CAM1_RAW_FILE:-}"
INTEGRITY_MODE="${INTEGRITY_MODE:-strict}"
BAG_PREFIX="${BAG_PREFIX:-${CAMERA_PROFILE}_from_raw}"
EVENT_DELTA_T="${EVENT_DELTA_T:-0.001}"
PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS:-3}"
[ -n "${CAM0_RAW_FILE}" ] && [ -n "${CAM1_RAW_FILE}" ] || {
  echo "Set CAM0_RAW_FILE and CAM1_RAW_FILE." >&2
  exit 1
}
if [ "${INTEGRITY_MODE}" != "strict" ] && [ "${INTEGRITY_MODE}" != "relaxed" ]; then
  echo "INTEGRITY_MODE must be strict or relaxed." >&2
  exit 1
fi
require_safe_prefix "${BAG_PREFIX}"
cam0_raw="$(to_container_path "${CAM0_RAW_FILE}")"
cam1_raw="$(to_container_path "${CAM1_RAW_FILE}")"
case "${CAMERA_PROFILE}" in
  prophesee_evk1_vga*) DATA_ROOT=/workspace/data/prophesee/evk1_vga; EXPECTED_WIDTH=640; EXPECTED_HEIGHT=480; EXPECTED_GENERATION_MAJOR=3; EXPECTED_SYSTEM_IDS=21,28 ;;
  prophesee_evk4*) DATA_ROOT=/workspace/data/prophesee; EXPECTED_WIDTH=1280; EXPECTED_HEIGHT=720; EXPECTED_GENERATION_MAJOR=4; EXPECTED_SYSTEM_IDS=49 ;;
  *) echo "Unsupported CAMERA_PROFILE for paired RAW conversion." >&2; exit 1 ;;
esac

run_in_container_as_root env \
  INSIDE_CONTAINER=1 CAM0_RAW_FILE="${cam0_raw}" CAM1_RAW_FILE="${cam1_raw}" \
  INTEGRITY_MODE="${INTEGRITY_MODE}" BAG_PREFIX="${BAG_PREFIX}" \
  EVENT_DELTA_T="${EVENT_DELTA_T}" DATA_ROOT="${DATA_ROOT}" \
  EXPECTED_WIDTH="${EXPECTED_WIDTH}" EXPECTED_HEIGHT="${EXPECTED_HEIGHT}" \
  EXPECTED_GENERATION_MAJOR="${EXPECTED_GENERATION_MAJOR}" \
  EXPECTED_SYSTEM_IDS="${EXPECTED_SYSTEM_IDS}" \
  PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS}" \
  ROS_DEVEL_SPACE="${ROS_DEVEL_SPACE}" \
  bash -lc '
    set -euo pipefail
    source /opt/ros/noetic/setup.bash
    source "${ROS_DEVEL_SPACE}/setup.bash"
    source /workspace/scripts/lib/prophesee_common.sh
    if rosnode list >/dev/null 2>&1; then
      echo "A ROS master is already running. Stop live drivers before conversion." >&2
      exit 1
    fi
    info0="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${CAM0_RAW_FILE}")"
    info1="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${CAM1_RAW_FILE}")"
    validate_raw_profile "${info0}" "${EXPECTED_WIDTH}" "${EXPECTED_HEIGHT}" "${EXPECTED_GENERATION_MAJOR}" "${EXPECTED_SYSTEM_IDS}"
    validate_raw_profile "${info1}" "${EXPECTED_WIDTH}" "${EXPECTED_HEIGHT}" "${EXPECTED_GENERATION_MAJOR}" "${EXPECTED_SYSTEM_IDS}"
    serial0="$(printf "%s\n" "${info0}" | kv_value serial)"
    serial1="$(printf "%s\n" "${info1}" | kv_value serial)"
    system_id0="$(printf "%s\n" "${info0}" | kv_value system_id)"
    system_id1="$(printf "%s\n" "${info1}" | kv_value system_id)"
    [ "${serial0}" != "${serial1}" ] || { echo "Paired RAW files must come from different serials." >&2; exit 1; }
    first0="$(printf "%s\n" "${info0}" | kv_value first_timestamp_us)"
    first1="$(printf "%s\n" "${info1}" | kv_value first_timestamp_us)"
    last0="$(printf "%s\n" "${info0}" | kv_value last_timestamp_us)"
    last1="$(printf "%s\n" "${info1}" | kv_value last_timestamp_us)"
    raw_events0="$(printf "%s\n" "${info0}" | kv_value cd_event_count)"
    raw_events1="$(printf "%s\n" "${info1}" | kv_value cd_event_count)"
    raw_triggers0="$(printf "%s\n" "${info0}" | kv_value trigger_event_count)"
    raw_triggers1="$(printf "%s\n" "${info1}" | kv_value trigger_event_count)"
    timestamp_base="$(python3 -c "print(min(int(${first0}), int(${first1})))")"
    duration="$(python3 -c "print(max(int(${last0}), int(${last1})) - int(${timestamp_base}))")"
    epoch="$(python3 -c "import time; print(time.time() + float(${PLAYBACK_LEAD_SECONDS}))")"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    base="${BAG_PREFIX}_${serial0}_${serial1}_${stamp}"
    bag_file="${DATA_ROOT}/rosbag/${base}.bag"
    cam0_temp_bag="${DATA_ROOT}/rosbag/.${base}.cam0.tmp.bag"
    cam1_temp_bag="${DATA_ROOT}/rosbag/.${base}.cam1.tmp.bag"
    manifest="${DATA_ROOT}/manifests/${base}.bag_pair.yaml"
    mkdir -p "${DATA_ROOT}/rosbag" "${DATA_ROOT}/manifests"

    core_pid=""; cam0_bag_pid=""; cam1_bag_pid=""; replay_pid=""
    cleanup() {
      set +e
      for pid in "${replay_pid}" "${cam0_bag_pid}" "${cam1_bag_pid}" "${core_pid}"; do
        [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null && kill -INT "${pid}" 2>/dev/null
      done
      rm -f "${cam0_temp_bag}" "${cam1_temp_bag}" \
        "${cam0_temp_bag}.active" "${cam1_temp_bag}.active"
    }
    trap cleanup EXIT INT TERM
    roscore >/tmp/prophesee_pair_roscore.log 2>&1 & core_pid=$!
    for _ in $(seq 1 100); do rosnode list >/dev/null 2>&1 && break; sleep 0.1; done
    rosbag record -O "${cam0_temp_bag}" /cam0/events /cam0/camera_info /cam0/ext_trigger \
      >/tmp/prophesee_pair_cam0_rosbag.log 2>&1 & cam0_bag_pid=$!
    rosbag record -O "${cam1_temp_bag}" /cam1/events /cam1/camera_info /cam1/ext_trigger \
      >/tmp/prophesee_pair_cam1_rosbag.log 2>&1 & cam1_bag_pid=$!
    watchdog="$(python3 -c "import math; print(math.ceil(${duration} / 1000000.0 + float(${PLAYBACK_LEAD_SECONDS})) + 10)")"
    timeout --signal=INT --kill-after=5s "${watchdog}s" \
      roslaunch event_camera_lab_bringup prophesee_raw_pair_dvs_replay.launch \
      cam0_raw_file:="${CAM0_RAW_FILE}" cam1_raw_file:="${CAM1_RAW_FILE}" \
      timestamp_offset_sec:="${epoch}" timestamp_base_us:="${timestamp_base}" \
      event_delta_t:="${EVENT_DELTA_T}" >/tmp/prophesee_pair_replay.log 2>&1 &
    replay_pid=$!
    set +e; wait "${replay_pid}"; replay_status=$?; set -e; replay_pid=""
    [ "${replay_status}" -eq 0 ] || {
      echo "Paired RAW replay failed with status ${replay_status}." >&2
      sed -n "1,180p" /tmp/prophesee_pair_replay.log >&2
      exit 1
    }
    sleep 0.5
    kill -INT "${cam0_bag_pid}" "${cam1_bag_pid}" 2>/dev/null || true
    wait "${cam0_bag_pid}" || true; cam0_bag_pid=""
    wait "${cam1_bag_pid}" || true; cam1_bag_pid=""
    rosbag check "${cam0_temp_bag}"
    rosbag check "${cam1_temp_bag}"
    python3 /workspace/scripts/lib/merge_event_bags.py \
      --output "${bag_file}" "${cam0_temp_bag}" "${cam1_temp_bag}"
    rm -f "${cam0_temp_bag}" "${cam1_temp_bag}"
    rosbag check "${bag_file}"

    bag_events0="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam0/events | kv_value event_count)"
    bag_events1="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam1/events | kv_value event_count)"
    bag_triggers0="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam0/ext_trigger | kv_value event_count)"
    bag_triggers1="$(python3 /workspace/scripts/lib/inspect_event_bag.py "${bag_file}" --topic /cam1/ext_trigger | kv_value event_count)"
    result="$(python3 -c "r=[${raw_events0},${raw_events1},${raw_triggers0},${raw_triggers1}]; b=[${bag_events0},${bag_events1},${bag_triggers0},${bag_triggers1}]; d=[abs(x-y) for x,y in zip(r,b)]; ratios=[d[i]/r[i] if r[i] else (0 if d[i]==0 else 1) for i in range(4)]; print(max(d), max(ratios))")"
    read -r max_difference max_ratio <<<"${result}"
    passed=false
    if [ "${INTEGRITY_MODE}" = strict ]; then
      [ "${max_difference}" -eq 0 ] && passed=true
    else
      python3 -c "raise SystemExit(0 if float(${max_ratio}) <= 0.001 else 1)" && passed=true
    fi
    python3 /workspace/scripts/lib/write_recording_manifest.py \
      --output "${manifest}" --field "data_kind=rosbag_from_raw_pair" \
      --field "data_file=${bag_file}" --field "sha256=$(sha256sum "${bag_file}" | awk "{print \$1}")" \
      --field "cam0_raw=${CAM0_RAW_FILE}" --field "cam1_raw=${CAM1_RAW_FILE}" \
      --field "cam0_raw_sha256=$(sha256sum "${CAM0_RAW_FILE}" | awk "{print \$1}")" \
      --field "cam1_raw_sha256=$(sha256sum "${CAM1_RAW_FILE}" | awk "{print \$1}")" \
      --field "cam0_serial=${serial0}" --field "cam1_serial=${serial1}" \
      --field "cam0_system_id=${system_id0}" --field "cam1_system_id=${system_id1}" \
      --field "width=${EXPECTED_WIDTH}" --field "height=${EXPECTED_HEIGHT}" \
      --field "generation_major=${EXPECTED_GENERATION_MAJOR}" \
      --field "cam0_raw_event_count=${raw_events0}" --field "cam1_raw_event_count=${raw_events1}" \
      --field "cam0_bag_event_count=${bag_events0}" --field "cam1_bag_event_count=${bag_events1}" \
      --field "cam0_raw_trigger_count=${raw_triggers0}" --field "cam1_raw_trigger_count=${raw_triggers1}" \
      --field "cam0_bag_trigger_count=${bag_triggers0}" --field "cam1_bag_trigger_count=${bag_triggers1}" \
      --field "integrity_mode=${INTEGRITY_MODE}" --field "integrity_passed=${passed}" \
      --field "timestamp_policy=shared_raw_origin" --field "sync_verified=false" \
      --field "bag_ordering=merged_by_first_event_or_header_timestamp" \
      --field "event_delta_t_s=${EVENT_DELTA_T}" \
      --field "cam0_calibration_sha256=$(calibration_sha "${serial0}")" \
      --field "cam1_calibration_sha256=$(calibration_sha "${serial1}")" \
      --field "openeb_version=${OPENEB_VERSION}" --field "openeb_commit=${OPENEB_COMMIT}" \
      --field "project_commit=$(project_commit)" --field "project_dirty=$(project_dirty)"
    echo "Bag: ${bag_file}"
    echo "Manifest: ${manifest}"
    [ "${passed}" = true ] || { echo "Pair integrity check failed." >&2; exit 2; }
  '
