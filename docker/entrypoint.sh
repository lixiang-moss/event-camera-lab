#!/usr/bin/env bash
set -e

if [ -f "/opt/ros/${ROS_DISTRO:-noetic}/setup.bash" ]; then
  # shellcheck source=/dev/null
  source "/opt/ros/${ROS_DISTRO:-noetic}/setup.bash"
fi

if [ -f "${ROS_WS:-/workspace/ros_ws}/devel/setup.bash" ]; then
  # shellcheck source=/dev/null
  source "${ROS_WS:-/workspace/ros_ws}/devel/setup.bash"
fi

exec "$@"
