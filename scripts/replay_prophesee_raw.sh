#!/usr/bin/env bash
set -euo pipefail

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4}"
source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"
source "$(dirname "$0")/lib/prophesee_common.sh"

RAW_FILE="${RAW_FILE:-}"
WITH_VIEWER="${WITH_VIEWER:-false}"
AUTO_STOP="${AUTO_STOP:-true}"
EVENT_DELTA_T="${EVENT_DELTA_T:-0.001}"
PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS:-3}"

case "${CAMERA_PROFILE}" in
  prophesee_evk1_vga*) EXPECTED_WIDTH=640; EXPECTED_HEIGHT=480; EXPECTED_GENERATION_MAJOR=3; EXPECTED_SYSTEM_IDS=21,28 ;;
  prophesee_evk4*) EXPECTED_WIDTH=1280; EXPECTED_HEIGHT=720; EXPECTED_GENERATION_MAJOR=4; EXPECTED_SYSTEM_IDS=49 ;;
  *) echo "Unsupported CAMERA_PROFILE for Prophesee RAW replay." >&2; exit 1 ;;
esac

if [ -z "${RAW_FILE}" ]; then
  echo "Set RAW_FILE to a recording inside the project or /workspace." >&2
  exit 1
fi
container_raw_file="$(to_container_path "${RAW_FILE}")"

run_in_container_as_root env \
  RAW_FILE="${container_raw_file}" \
  WITH_VIEWER="${WITH_VIEWER}" \
  AUTO_STOP="${AUTO_STOP}" \
  EVENT_DELTA_T="${EVENT_DELTA_T}" \
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
    test -f "${RAW_FILE}"
    info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${RAW_FILE}")"
    validate_raw_profile "${info}" "${EXPECTED_WIDTH}" "${EXPECTED_HEIGHT}" "${EXPECTED_GENERATION_MAJOR}" "${EXPECTED_SYSTEM_IDS}"
    first_timestamp_us="$(printf "%s\n" "${info}" | kv_value first_timestamp_us)"
    duration_us="$(printf "%s\n" "${info}" | kv_value duration_us)"
    timestamp_offset_sec="$(python3 -c "import time; print(time.time() + float(${PLAYBACK_LEAD_SECONDS}))")"
    command=(roslaunch event_camera_lab_bringup prophesee_raw_dvs_replay.launch
      raw_file:="${RAW_FILE}"
      timestamp_offset_sec:="${timestamp_offset_sec}"
      timestamp_base_us:="${first_timestamp_us}"
      event_delta_t:="${EVENT_DELTA_T}"
      with_renderer:="${WITH_VIEWER}")
    if [ "${AUTO_STOP}" = "true" ]; then
      wait_seconds="$(python3 -c "import math; print(math.ceil(${duration_us} / 1000000.0 + float(${PLAYBACK_LEAD_SECONDS})) + 4)")"
      timeout --signal=INT "${wait_seconds}" "${command[@]}" || [ "$?" -eq 124 ]
    else
      "${command[@]}"
    fi
  '
