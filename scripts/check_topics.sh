#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

EVENT_TOPIC="${EVENT_TOPIC:-/dvs/events}"
HZ_WINDOW="${HZ_WINDOW:-8}"

run_in_container bash -lc "
  source /opt/ros/noetic/setup.bash
  source /workspace/ros_ws/devel/setup.bash
  echo '== rostopic list =='
  rostopic list
  echo
  echo '== event topic rate: ${EVENT_TOPIC} =='
  timeout ${HZ_WINDOW}s rostopic hz ${EVENT_TOPIC} || true
"
