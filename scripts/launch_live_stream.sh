#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

CAMERA_PROFILE="${CAMERA_PROFILE:-current_davis}"
LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-}"
LAUNCH_FILE="${LAUNCH_FILE:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
CAMERA_SERIAL="${CAMERA_SERIAL:-}"

detect_single_prophesee_serial() {
  run_in_container_as_root bash -lc "
    source /opt/ros/noetic/setup.bash
    source /workspace/ros_ws/devel/setup.bash
    rosrun event_camera_prophesee_tools prophesee_device_info --single-serial
  "
}

resolve_prophesee_serial() {
  local detected_serial
  detected_serial="$(detect_single_prophesee_serial)"
  if [ -n "${CAMERA_SERIAL}" ] && [ "${CAMERA_SERIAL}" != "${detected_serial}" ]; then
    echo "CAMERA_SERIAL=${CAMERA_SERIAL} does not match detected EVK serial ${detected_serial}." >&2
    return 1
  fi
  printf '%s\n' "${detected_serial}"
}

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
  current_davis_dual)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dual_live_stream.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  current_davis_dual_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dual_live_stream_with_renderer.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  dvs128_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-dvs_renderer}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvs_mono.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  dvxplorer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvxplorer_live_stream.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  dvxplorer_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvxplorer_live_stream_with_renderer.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${EXTRA_ARGS}"
    ;;
  prophesee_evk4)
    CAMERA_SERIAL="$(resolve_prophesee_serial)"
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk4_live_stream.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} camera_serial:=${CAMERA_SERIAL} ${EXTRA_ARGS}"
    ;;
  prophesee_evk4_with_renderer)
    CAMERA_SERIAL="$(resolve_prophesee_serial)"
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk4_live_stream_with_renderer.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} camera_serial:=${CAMERA_SERIAL} ${EXTRA_ARGS}"
    ;;
  prophesee_evk4_calibration)
    CAMERA_SERIAL="$(resolve_prophesee_serial)"
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk4_intrinsic_calibration.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} camera_serial:=${CAMERA_SERIAL} ${EXTRA_ARGS}"
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
    echo "Supported: current_davis, current_davis_with_renderer, current_davis_dual, current_davis_dual_with_renderer, dvs128_with_renderer, dvxplorer, dvxplorer_with_renderer, prophesee_evk4, prophesee_evk4_with_renderer, prophesee_evk4_calibration, custom" >&2
    exit 1
    ;;
esac

run_in_container_as_root bash -lc "
  source /opt/ros/noetic/setup.bash
  source /workspace/ros_ws/devel/setup.bash
  ${COMMAND}
"
