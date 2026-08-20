#!/usr/bin/env bash
set -euo pipefail

CAMERA_PROFILE="${CAMERA_PROFILE:-prophesee_evk4}"
source "$(dirname "$0")/lib/common.sh"
configure_runtime "${CAMERA_PROFILE}"
source "$(dirname "$0")/lib/prophesee_common.sh"

RAW_FILE="${RAW_FILE:-}"
INTEGRITY_MODE="${INTEGRITY_MODE:-strict}"
BAG_PREFIX="${BAG_PREFIX:-${CAMERA_PROFILE}_from_raw}"
EVENT_DELTA_T="${EVENT_DELTA_T:-0.001}"
PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS:-3}"

if [ -z "${RAW_FILE}" ]; then
  echo "Set RAW_FILE to a recording inside the project or /workspace." >&2
  exit 1
fi
if [ "${INTEGRITY_MODE}" != "strict" ] && [ "${INTEGRITY_MODE}" != "relaxed" ]; then
  echo "INTEGRITY_MODE must be strict or relaxed." >&2
  exit 1
fi
require_safe_prefix "${BAG_PREFIX}"
container_raw_file="$(to_container_path "${RAW_FILE}")"

case "${CAMERA_PROFILE}" in
  prophesee_evk1_vga*) DATA_ROOT=/workspace/data/prophesee/evk1_vga; EXPECTED_WIDTH=640; EXPECTED_HEIGHT=480; EXPECTED_GENERATION_MAJOR=3; EXPECTED_SYSTEM_IDS=21,28 ;;
  prophesee_evk4*) DATA_ROOT=/workspace/data/prophesee; EXPECTED_WIDTH=1280; EXPECTED_HEIGHT=720; EXPECTED_GENERATION_MAJOR=4; EXPECTED_SYSTEM_IDS=49 ;;
  *) echo "Unsupported CAMERA_PROFILE for Prophesee RAW conversion." >&2; exit 1 ;;
esac

run_in_container_as_root env \
  RAW_FILE="${container_raw_file}" \
  INTEGRITY_MODE="${INTEGRITY_MODE}" \
  BAG_PREFIX="${BAG_PREFIX}" \
  EVENT_DELTA_T="${EVENT_DELTA_T}" \
  DATA_ROOT="${DATA_ROOT}" \
  EXPECTED_WIDTH="${EXPECTED_WIDTH}" EXPECTED_HEIGHT="${EXPECTED_HEIGHT}" \
  EXPECTED_GENERATION_MAJOR="${EXPECTED_GENERATION_MAJOR}" \
  EXPECTED_SYSTEM_IDS="${EXPECTED_SYSTEM_IDS}" \
  PLAYBACK_LEAD_SECONDS="${PLAYBACK_LEAD_SECONDS}" \
  ROS_DEVEL_SPACE="${ROS_DEVEL_SPACE}" \
  bash /workspace/scripts/lib/convert_prophesee_raw_to_rosbag_inside.sh
