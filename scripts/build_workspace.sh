#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

PACKAGES="${PACKAGES:-catkin_simple dvs_msgs dvs_ros_driver davis_ros_driver dvxplorer_ros_driver dvs_renderer dvs_file_writer prophesee_event_msgs prophesee_ros_driver event_camera_prophesee_tools dvs_calibration event_camera_lab_bringup}"

run_in_container bash -lc "
  source /opt/ros/noetic/setup.bash
  cd /workspace/ros_ws
  if [ ! -d src ]; then
    echo 'Missing /workspace/ros_ws/src' >&2
    exit 1
  fi
  rosdep update --rosdistro noetic || true
  rosdep install --from-paths src --ignore-src --rosdistro noetic -y
  catkin config --init --mkdirs --extend /opt/ros/noetic --merge-devel --cmake-args -DCMAKE_BUILD_TYPE=Release -DCATKIN_ENABLE_TESTING=OFF
  catkin build ${PACKAGES}
"
