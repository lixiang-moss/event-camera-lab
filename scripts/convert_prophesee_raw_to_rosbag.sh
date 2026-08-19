#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/prophesee_common.sh"

RAW_FILE="${RAW_FILE:-}"
INTEGRITY_MODE="${INTEGRITY_MODE:-strict}"
BAG_PREFIX="${BAG_PREFIX:-evk4_from_raw}"
EVENT_DELTA_T="${EVENT_DELTA_T:-0.001}"

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

run_in_container_as_root env \
  RAW_FILE="${container_raw_file}" \
  INTEGRITY_MODE="${INTEGRITY_MODE}" \
  BAG_PREFIX="${BAG_PREFIX}" \
  EVENT_DELTA_T="${EVENT_DELTA_T}" \
  bash /workspace/scripts/lib/convert_prophesee_raw_to_rosbag_inside.sh
