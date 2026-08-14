#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

EVENT_TOPICS="${EVENT_TOPICS:-${EVENT_TOPIC:-/dvs/events}}"
BAG_DIR="${BAG_DIR:-/workspace/data}"
BAG_PREFIX="${BAG_PREFIX:-event_camera}"
DURATION="${DURATION:-30}"

mkdir -p "${PROJECT_ROOT}/data"

run_in_container bash -lc "
  source /opt/ros/noetic/setup.bash
  source /workspace/ros_ws/devel/setup.bash
  mkdir -p '${BAG_DIR}'
  topics=(${EVENT_TOPICS})
  rosbag record --duration=${DURATION} -O '${BAG_DIR}/${BAG_PREFIX}_$(date +%Y%m%d_%H%M%S).bag' \"\${topics[@]}\"
"
