#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/nrv_viewer_common.sh"

if [ -z "${DISPLAY:-}" ]; then
  echo "DISPLAY is empty; start this command from an X11 desktop session." >&2
  exit 1
fi

prepare_nrv_data_directories

xhost_rule_added=false
cleanup_xhost() {
  if [ "${xhost_rule_added}" = true ]; then
    xhost -SI:localuser:root >/dev/null 2>&1 || true
  fi
}
trap cleanup_xhost EXIT INT TERM

if command -v xhost >/dev/null 2>&1; then
  if xhost +SI:localuser:root >/dev/null 2>&1; then
    xhost_rule_added=true
  fi
fi

nrv_compose run --rm "${NRV_SERVICE_NAME}"
