#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4}"
configure_runtime "${CAMERA_PROFILE}"

CAMERA_SERIAL="${CAMERA_SERIAL:-}"
if [ -z "${CAMERA_SERIAL}" ]; then
  CAMERA_SERIAL="$(run_in_container_as_root bash -lc '
    source /opt/ros/noetic/setup.bash
    source ${ROS_DEVEL_SPACE}/setup.bash
    rosrun event_camera_prophesee_tools prophesee_device_info --single-serial
  ')"
fi

INPUT_FILE="${INPUT_FILE:-/workspace/config/camera_info/prophesee_${CAMERA_SERIAL}.yaml}"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/config/calibration/prophesee/${CAMERA_SERIAL}}"

run_in_container env \
  ROS_DEVEL_SPACE="${ROS_DEVEL_SPACE}" \
  CAMERA_SERIAL="${CAMERA_SERIAL}" \
  INPUT_FILE="${INPUT_FILE}" \
  OUTPUT_DIR="${OUTPUT_DIR}" \
  bash -lc '
    set -euo pipefail
    test -f "${INPUT_FILE}"
    python3 /workspace/scripts/lib/export_prophesee_calibration.py \
      --input "${INPUT_FILE}" \
      --output-dir "${OUTPUT_DIR}" \
      --serial "${CAMERA_SERIAL}"
  '
