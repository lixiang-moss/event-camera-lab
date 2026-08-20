#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
SERVICE_NAME="${SERVICE_NAME:-event-camera-ros}"
IMAGE_NAME="${IMAGE_NAME:-event-camera-lab:noetic}"
ROS_WS="${PROJECT_ROOT}/ros_ws"

configure_runtime() {
  local profile="${1:-${CAMERA_PROFILE:-}}"
  case "${profile}" in
    prophesee_evk1_vga*)
      SERVICE_NAME="event-camera-openeb31-ros"
      IMAGE_NAME="event-camera-lab:openeb31-noetic"
      ROS_DEVEL_SPACE="/workspace/ros_ws/devel_openeb31"
      ;;
    *)
      SERVICE_NAME="event-camera-ros"
      IMAGE_NAME="event-camera-lab:noetic"
      ROS_DEVEL_SPACE="/workspace/ros_ws/devel"
      ;;
  esac
  export SERVICE_NAME IMAGE_NAME ROS_DEVEL_SPACE
}

source_ros_setup_command() {
  printf 'source /opt/ros/noetic/setup.bash && source %q/setup.bash' "${ROS_DEVEL_SPACE:-/workspace/ros_ws/devel}"
}

compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

run_in_container() {
  compose run --rm "${SERVICE_NAME}" "$@"
}

run_in_container_as_root() {
  compose run --rm --user root "${SERVICE_NAME}" "$@"
}
