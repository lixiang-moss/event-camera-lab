#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

configure_runtime "${CAMERA_PROFILE:-}"
compose build "${SERVICE_NAME}"
