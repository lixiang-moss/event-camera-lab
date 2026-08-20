#!/usr/bin/env bash
set -euo pipefail

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4_dual}"
source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"
source "$(dirname "$0")/lib/prophesee_common.sh"

CAM0_RAW_FILE="${CAM0_RAW_FILE:-}"
CAM1_RAW_FILE="${CAM1_RAW_FILE:-}"
WITH_VIEWER="${WITH_VIEWER:-false}"
AUTO_STOP="${AUTO_STOP:-true}"
EVENT_DELTA_T="${EVENT_DELTA_T:-0.001}"
PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS:-3}"
case "${CAMERA_PROFILE}" in
  prophesee_evk1_vga*) EXPECTED_WIDTH=640; EXPECTED_HEIGHT=480; EXPECTED_GENERATION_MAJOR=3; EXPECTED_SYSTEM_IDS=21,28 ;;
  prophesee_evk4*) EXPECTED_WIDTH=1280; EXPECTED_HEIGHT=720; EXPECTED_GENERATION_MAJOR=4; EXPECTED_SYSTEM_IDS=49 ;;
  *) echo "Unsupported CAMERA_PROFILE for paired RAW replay." >&2; exit 1 ;;
esac
if [ -z "${CAM0_RAW_FILE}" ] || [ -z "${CAM1_RAW_FILE}" ]; then
  echo "Set CAM0_RAW_FILE and CAM1_RAW_FILE." >&2
  exit 1
fi
cam0_raw="$(to_container_path "${CAM0_RAW_FILE}")"
cam1_raw="$(to_container_path "${CAM1_RAW_FILE}")"

run_in_container_as_root env \
  CAM0_RAW_FILE="${cam0_raw}" CAM1_RAW_FILE="${cam1_raw}" \
  WITH_VIEWER="${WITH_VIEWER}" AUTO_STOP="${AUTO_STOP}" \
  EVENT_DELTA_T="${EVENT_DELTA_T}" ROS_DEVEL_SPACE="${ROS_DEVEL_SPACE}" \
  EXPECTED_WIDTH="${EXPECTED_WIDTH}" EXPECTED_HEIGHT="${EXPECTED_HEIGHT}" \
  EXPECTED_GENERATION_MAJOR="${EXPECTED_GENERATION_MAJOR}" \
  EXPECTED_SYSTEM_IDS="${EXPECTED_SYSTEM_IDS}" \
  PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS}" \
  bash -lc '
    set -euo pipefail
    source /opt/ros/noetic/setup.bash
    source "${ROS_DEVEL_SPACE}/setup.bash"
    source /workspace/scripts/lib/prophesee_common.sh
    info0="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${CAM0_RAW_FILE}")"
    info1="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${CAM1_RAW_FILE}")"
    validate_raw_profile "${info0}" "${EXPECTED_WIDTH}" "${EXPECTED_HEIGHT}" "${EXPECTED_GENERATION_MAJOR}" "${EXPECTED_SYSTEM_IDS}"
    validate_raw_profile "${info1}" "${EXPECTED_WIDTH}" "${EXPECTED_HEIGHT}" "${EXPECTED_GENERATION_MAJOR}" "${EXPECTED_SYSTEM_IDS}"
    serial0="$(printf "%s\n" "${info0}" | kv_value serial)"
    serial1="$(printf "%s\n" "${info1}" | kv_value serial)"
    [ "${serial0}" != "${serial1}" ] || { echo "Paired RAW files must come from different serials." >&2; exit 1; }
    first0="$(printf "%s\n" "${info0}" | kv_value first_timestamp_us)"
    first1="$(printf "%s\n" "${info1}" | kv_value first_timestamp_us)"
    last0="$(printf "%s\n" "${info0}" | kv_value last_timestamp_us)"
    last1="$(printf "%s\n" "${info1}" | kv_value last_timestamp_us)"
    base="$(python3 -c "print(min(int(${first0}), int(${first1})))")"
    duration="$(python3 -c "print(max(int(${last0}), int(${last1})) - int(${base}))")"
    epoch="$(python3 -c "import time; print(time.time() + float(${PLAYBACK_LEAD_SECONDS}))")"
    command=(roslaunch event_camera_lab_bringup prophesee_raw_pair_dvs_replay.launch
      cam0_raw_file:="${CAM0_RAW_FILE}" cam1_raw_file:="${CAM1_RAW_FILE}"
      timestamp_offset_sec:="${epoch}" timestamp_base_us:="${base}"
      event_delta_t:="${EVENT_DELTA_T}" with_renderer:="${WITH_VIEWER}")
    if [ "${AUTO_STOP}" = "true" ]; then
      wait_seconds="$(python3 -c "import math; print(math.ceil(${duration} / 1000000.0 + float(${PLAYBACK_LEAD_SECONDS})) + 4)")"
      timeout --signal=INT "${wait_seconds}" "${command[@]}" || [ "$?" -eq 124 ]
    else
      "${command[@]}"
    fi
  '
