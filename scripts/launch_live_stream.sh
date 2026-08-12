#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

CAMERA_PROFILE="${CAMERA_PROFILE:-current_davis}"
LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-}"
LAUNCH_FILE="${LAUNCH_FILE:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

case "${CAMERA_PROFILE}" in
  current_davis)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-current_live_stream.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  current_davis_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-current_live_stream_with_renderer.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  dvs128_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-dvs_renderer}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvs_mono.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  dvxplorer_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-dvs_renderer}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvxplorer_mono.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  custom)
    if [ -z "${LAUNCH_PACKAGE}" ] || [ -z "${LAUNCH_FILE}" ]; then
      echo "For CAMERA_PROFILE=custom, set LAUNCH_PACKAGE and LAUNCH_FILE." >&2
      exit 1
    fi
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  *)
    echo "Unknown CAMERA_PROFILE: ${CAMERA_PROFILE}" >&2
    echo "Supported: current_davis, current_davis_with_renderer, dvs128_with_renderer, dvxplorer_with_renderer, custom" >&2
    exit 1
    ;;
esac

run_in_container_as_root bash -lc "
  source /opt/ros/noetic/setup.bash
  source /workspace/ros_ws/devel/setup.bash
  ${COMMAND}
"
