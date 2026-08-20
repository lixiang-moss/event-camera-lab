#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_RULE="${PROJECT_ROOT}/config/udev/88-cyusb.rules"
TARGET_RULE="/etc/udev/rules.d/88-cyusb.rules"

if [ ! -f "${SOURCE_RULE}" ]; then
  echo "Missing ${SOURCE_RULE}" >&2
  exit 1
fi

sudo install -m 0644 "${SOURCE_RULE}" "${TARGET_RULE}"
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Installed ${TARGET_RULE}. Unplug and reconnect the Prophesee camera before testing access."
