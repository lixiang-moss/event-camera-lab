#!/usr/bin/env bash
CAMERA_PROFILE="${CAMERA_PROFILE:-current_davis}"
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"

LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-}"
LAUNCH_FILE="${LAUNCH_FILE:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
CAMERA_SERIAL="${CAMERA_SERIAL:-}"
CAM0_SERIAL="${CAM0_SERIAL:-}"
CAM1_SERIAL="${CAM1_SERIAL:-}"
CAM0_BIAS_FILE="${CAM0_BIAS_FILE:-}"
CAM1_BIAS_FILE="${CAM1_BIAS_FILE:-}"
CAM0_DEVICE_IDENTIFIER="${CAM0_DEVICE_IDENTIFIER:-}"
CAM1_DEVICE_IDENTIFIER="${CAM1_DEVICE_IDENTIFIER:-}"
BIAS_FILE="${BIAS_FILE:-}"
SYNC_MODE="${SYNC_MODE:-standalone}"
REQUIRE_SERIALS="${REQUIRE_SERIALS:-false}"

require_distinct_serials() {
  if [ -z "${CAM0_SERIAL}" ] || [ -z "${CAM1_SERIAL}" ]; then
    echo "CAM0_SERIAL and CAM1_SERIAL are required for ${CAMERA_PROFILE}." >&2
    exit 1
  fi
  if [ "${CAM0_SERIAL}" = "${CAM1_SERIAL}" ]; then
    echo "CAM0_SERIAL and CAM1_SERIAL must identify different cameras." >&2
    exit 1
  fi
}

require_prophesee_sync_mode() {
  case "${SYNC_MODE}" in
    standalone|master_slave) ;;
    *) echo "SYNC_MODE must be standalone or master_slave." >&2; exit 1 ;;
  esac
}

optional_serial_args() {
  if [ "${REQUIRE_SERIALS}" = "true" ] && { [ -z "${CAM0_SERIAL}" ] || [ -z "${CAM1_SERIAL}" ]; }; then
    echo "REQUIRE_SERIALS=true requires CAM0_SERIAL and CAM1_SERIAL." >&2
    exit 1
  fi
  if { [ -n "${CAM0_SERIAL}" ] && [ -z "${CAM1_SERIAL}" ]; } ||
     { [ -z "${CAM0_SERIAL}" ] && [ -n "${CAM1_SERIAL}" ]; }; then
    echo "Set both CAM0_SERIAL and CAM1_SERIAL, or neither." >&2
    exit 1
  fi
  if [ -n "${CAM0_SERIAL}" ] && [ "${CAM0_SERIAL}" = "${CAM1_SERIAL}" ]; then
    echo "CAM0_SERIAL and CAM1_SERIAL must identify different cameras." >&2
    exit 1
  fi
  printf 'cam0_serial:=%q cam1_serial:=%q' "${CAM0_SERIAL}" "${CAM1_SERIAL}"
}

detect_single_prophesee_device() {
  run_in_container_as_root bash -lc "
    source /opt/ros/noetic/setup.bash
    source ${ROS_DEVEL_SPACE}/setup.bash
    rosrun event_camera_prophesee_tools prophesee_device_info
  "
}

resolve_prophesee_serial() {
  local device_info detected_serial detected_system_id expected_system_ids
  if ! device_info="$(detect_single_prophesee_device)"; then
    echo "Unable to inspect exactly one Prophesee camera for ${CAMERA_PROFILE}." >&2
    return 1
  fi
  detected_serial="$(printf '%s\n' "${device_info}" | awk -F= '$1 == "serial" {print $2}')"
  detected_system_id="$(printf '%s\n' "${device_info}" | awk -F= '$1 == "system_id" {print $2}')"
  case "${CAMERA_PROFILE}" in
    prophesee_evk1_vga*) expected_system_ids="21 28" ;;
    prophesee_evk4*) expected_system_ids="49" ;;
    *) expected_system_ids="" ;;
  esac
  if [[ " ${expected_system_ids} " != *" ${detected_system_id} "* ]]; then
    echo "Detected Prophesee system_ID=${detected_system_id}; ${CAMERA_PROFILE} expects ${expected_system_ids// / or }." >&2
    return 1
  fi
  if [ -n "${CAMERA_SERIAL}" ] && [ "${CAMERA_SERIAL}" != "${detected_serial}" ]; then
    echo "CAMERA_SERIAL=${CAMERA_SERIAL} does not match detected EVK serial ${detected_serial}." >&2
    return 1
  fi
  printf '%s\n' "${detected_serial}"
}

resolve_prophesee_source_identifier() {
  local serial="$1"
  local serial_quoted
  printf -v serial_quoted '%q' "${serial}"
  run_in_container_as_root bash -lc "
    source /opt/ros/noetic/setup.bash
    source ${ROS_DEVEL_SPACE}/setup.bash
    rosrun event_camera_prophesee_tools prophesee_device_info --resolve-source ${serial_quoted}
  "
}

prepare_prophesee_dual_devices() {
  if [[ " ${EXTRA_ARGS} " == *" --nodes "* ]]; then
    CAM0_DEVICE_IDENTIFIER="${CAM0_SERIAL}"
    CAM1_DEVICE_IDENTIFIER="${CAM1_SERIAL}"
    return
  fi
  CAM0_DEVICE_IDENTIFIER="$(resolve_prophesee_source_identifier "${CAM0_SERIAL}")" || {
    echo "CAM0_SERIAL=${CAM0_SERIAL} is not connected." >&2
    exit 1
  }
  CAM1_DEVICE_IDENTIFIER="$(resolve_prophesee_source_identifier "${CAM1_SERIAL}")" || {
    echo "CAM1_SERIAL=${CAM1_SERIAL} is not connected." >&2
    exit 1
  }
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
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} $(optional_serial_args) ${EXTRA_ARGS}"
    ;;
  current_davis_dual_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dual_live_stream_with_renderer.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} $(optional_serial_args) ${EXTRA_ARGS}"
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
  dvxplorer_dual)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvxplorer_dual_live_stream.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} $(optional_serial_args) ${EXTRA_ARGS}"
    ;;
  dvxplorer_dual_with_renderer)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvxplorer_dual_live_stream_with_renderer.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} $(optional_serial_args) ${EXTRA_ARGS}"
    ;;
  dvxplorer_dual_calibration)
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    LAUNCH_FILE="${LAUNCH_FILE:-dvxplorer_stereo_calibration.launch}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} $(optional_serial_args) ${EXTRA_ARGS}"
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
  prophesee_evk4_dual|prophesee_evk4_dual_with_renderer|prophesee_evk4_dual_calibration)
    require_distinct_serials
    require_prophesee_sync_mode
    prepare_prophesee_dual_devices
    TIMESTAMP_OFFSET_SEC="$(date +%s.%N)"
    case "${CAMERA_PROFILE}" in
      prophesee_evk4_dual) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk4_dual_live_stream.launch}" ;;
      prophesee_evk4_dual_with_renderer) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk4_dual_live_stream_with_renderer.launch}" ;;
      *) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk4_stereo_calibration.launch}" ;;
    esac
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} cam0_serial:=${CAM0_SERIAL} cam1_serial:=${CAM1_SERIAL} cam0_device_identifier:=${CAM0_DEVICE_IDENTIFIER} cam1_device_identifier:=${CAM1_DEVICE_IDENTIFIER} cam0_bias_file:=${CAM0_BIAS_FILE} cam1_bias_file:=${CAM1_BIAS_FILE} sync_mode:=${SYNC_MODE} timestamp_offset_sec:=${TIMESTAMP_OFFSET_SEC} ${EXTRA_ARGS}"
    ;;
  prophesee_evk1_vga|prophesee_evk1_vga_with_renderer|prophesee_evk1_vga_calibration)
    CAMERA_SERIAL="$(resolve_prophesee_serial)"
    case "${CAMERA_PROFILE}" in
      prophesee_evk1_vga) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk1_vga_live_stream.launch}" ;;
      prophesee_evk1_vga_with_renderer) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk1_vga_live_stream_with_renderer.launch}" ;;
      *) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk1_vga_intrinsic_calibration.launch}" ;;
    esac
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} camera_serial:=${CAMERA_SERIAL} bias_file:=${BIAS_FILE} ${EXTRA_ARGS}"
    ;;
  prophesee_evk1_vga_dual|prophesee_evk1_vga_dual_with_renderer|prophesee_evk1_vga_dual_calibration)
    require_distinct_serials
    require_prophesee_sync_mode
    prepare_prophesee_dual_devices
    TIMESTAMP_OFFSET_SEC="$(date +%s.%N)"
    case "${CAMERA_PROFILE}" in
      prophesee_evk1_vga_dual) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk1_vga_dual_live_stream.launch}" ;;
      prophesee_evk1_vga_dual_with_renderer) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk1_vga_dual_live_stream_with_renderer.launch}" ;;
      *) LAUNCH_FILE="${LAUNCH_FILE:-prophesee_evk1_vga_stereo_calibration.launch}" ;;
    esac
    LAUNCH_PACKAGE="${LAUNCH_PACKAGE:-event_camera_lab_bringup}"
    COMMAND="roslaunch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} cam0_serial:=${CAM0_SERIAL} cam1_serial:=${CAM1_SERIAL} cam0_device_identifier:=${CAM0_DEVICE_IDENTIFIER} cam1_device_identifier:=${CAM1_DEVICE_IDENTIFIER} cam0_bias_file:=${CAM0_BIAS_FILE} cam1_bias_file:=${CAM1_BIAS_FILE} sync_mode:=${SYNC_MODE} timestamp_offset_sec:=${TIMESTAMP_OFFSET_SEC} ${EXTRA_ARGS}"
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
    echo "See README.md for the supported camera profiles." >&2
    exit 1
    ;;
esac

run_in_container_as_root bash -lc "
  source /opt/ros/noetic/setup.bash
  source ${ROS_DEVEL_SPACE}/setup.bash
  ${COMMAND}
"
