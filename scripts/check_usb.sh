#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

echo "== Host USB devices =="
lsusb

echo
echo "== Container USB devices =="
run_in_container lsusb
