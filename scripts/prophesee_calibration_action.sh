#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4_calibration}"
configure_runtime "${CAMERA_PROFILE}"

ACTION="${1:-}"
case "${ACTION}" in
  start|save|reset)
    ;;
  *)
    echo "Usage: $0 {start|save|reset}" >&2
    exit 1
    ;;
esac

run_in_container bash -lc "
  source /opt/ros/noetic/setup.bash
  source ${ROS_DEVEL_SPACE}/setup.bash
  rosservice call /dvs_calibration/${ACTION}
"
