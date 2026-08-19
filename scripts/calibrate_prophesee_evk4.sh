#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export CAMERA_PROFILE=prophesee_evk4_calibration
export EXTRA_ARGS="${EXTRA_ARGS:-dots_w:=5 dots_h:=5 dot_distance:=0.05 blinking_time_us:=1000 blinking_time_tolerance_us:=500}"

exec "${PROJECT_ROOT}/scripts/launch_live_stream.sh"
