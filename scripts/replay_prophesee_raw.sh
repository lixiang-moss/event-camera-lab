#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

RAW_FILE="${RAW_FILE:-}"
ENABLE_DVS_ADAPTER="${ENABLE_DVS_ADAPTER:-true}"
WITH_VIEWER="${WITH_VIEWER:-false}"
AUTO_STOP="${AUTO_STOP:-true}"
EVENT_DELTA_T="${EVENT_DELTA_T:-0.001}"

if [ -z "${RAW_FILE}" ]; then
  echo "Set RAW_FILE to a recording inside the project or /workspace." >&2
  exit 1
fi

source "$(dirname "$0")/lib/prophesee_common.sh"
container_raw_file="$(to_container_path "${RAW_FILE}")"

run_in_container_as_root env \
  RAW_FILE="${container_raw_file}" \
  ENABLE_DVS_ADAPTER="${ENABLE_DVS_ADAPTER}" \
  WITH_VIEWER="${WITH_VIEWER}" \
  AUTO_STOP="${AUTO_STOP}" \
  EVENT_DELTA_T="${EVENT_DELTA_T}" \
  bash -lc '
    set -euo pipefail
    source /opt/ros/noetic/setup.bash
    source /workspace/ros_ws/devel/setup.bash
    source /workspace/scripts/lib/prophesee_common.sh
    test -f "${RAW_FILE}"
    info="$(rosrun event_camera_prophesee_tools prophesee_raw_info "${RAW_FILE}")"
    serial="$(printf "%s\n" "${info}" | kv_value serial)"
    duration_us="$(printf "%s\n" "${info}" | kv_value duration_us)"
    launch_file=prophesee_evk4_live_stream.launch
    if [ "${WITH_VIEWER}" = "true" ]; then
      launch_file=prophesee_evk4_live_stream_with_renderer.launch
    fi
    command=(roslaunch event_camera_lab_bringup "${launch_file}"
      camera_serial:="${serial}"
      raw_file_to_read:="${RAW_FILE}"
      enable_dvs_adapter:="${ENABLE_DVS_ADAPTER}"
      event_delta_t:="${EVENT_DELTA_T}")
    if [ "${AUTO_STOP}" = "true" ]; then
      wait_seconds="$(python3 -c "import math; print(math.ceil(${duration_us} / 1000000.0) + 2)")"
      timeout --signal=INT "${wait_seconds}" "${command[@]}" || [ "$?" -eq 124 ]
    else
      "${command[@]}"
    fi
  '
