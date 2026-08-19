#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

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
  source /workspace/ros_ws/devel/setup.bash
  rosservice call /dvs_calibration/${ACTION}
"
