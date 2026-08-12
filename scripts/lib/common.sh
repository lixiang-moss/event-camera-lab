#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
SERVICE_NAME="event-camera-ros"
IMAGE_NAME="event-camera-lab:noetic"
ROS_WS="${PROJECT_ROOT}/ros_ws"

compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

run_in_container() {
  compose run --rm "${SERVICE_NAME}" "$@"
}

run_in_container_as_root() {
  compose run --rm --user root "${SERVICE_NAME}" "$@"
}
