#!/usr/bin/env bash
set -e

source_ros_environment() {
  if [ -f "/opt/ros/${ROS_DISTRO:-noetic}/setup.bash" ]; then
    # shellcheck source=/dev/null
    source "/opt/ros/${ROS_DISTRO:-noetic}/setup.bash"
  fi

  local devel_space="${ROS_DEVEL_SPACE:-${ROS_WS:-/workspace/ros_ws}/devel}"
  if [ -f "${devel_space}/setup.bash" ]; then
    # shellcheck source=/dev/null
    source "${devel_space}/setup.bash"
  fi
}

# Keep the container command arguments away from catkin's setup utility.
source_ros_environment
unset -f source_ros_environment

exec "$@"
