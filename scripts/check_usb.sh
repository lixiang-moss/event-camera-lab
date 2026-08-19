#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

echo "== Host USB devices =="
lsusb

echo
echo "== Container USB devices =="
run_in_container lsusb

if lsusb -d 04b4:00f5 >/dev/null 2>&1; then
  echo
  echo "== Prophesee EVK4 checks =="
  lsusb -d 04b4:00f5

  if [ -f /etc/udev/rules.d/88-cyusb.rules ]; then
    echo "Host udev rule: installed"
  else
    echo "Host udev rule: missing"
    echo "Install it with: ./scripts/install_prophesee_udev_rules.sh"
  fi

  device_path="$(lsusb -d 04b4:00f5 | awk '{gsub(":", "", $4); print "/dev/bus/usb/" $2 "/" $4; exit}')"
  stat -c 'Host device node: %A %U:%G %n' "${device_path}"

  echo
  echo "== OpenEB HAL recognition =="
  if run_in_container bash -lc 'timeout 15s metavision_platform_info --system'; then
    :
  else
    echo "OpenEB could not open the EVK4. Check udev permissions and camera ownership." >&2
    exit 1
  fi
fi
