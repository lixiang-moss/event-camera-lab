#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/nrv_viewer_common.sh"

DELTA10_USB_ID="04b4:00f0"

echo "Host USB devices:"
host_usb="$(lsusb)"
printf '%s\n' "${host_usb}"

echo
echo "Container USB devices:"
container_usb="$(nrv_compose run --rm --entrypoint lsusb "${NRV_SERVICE_NAME}")"
printf '%s\n' "${container_usb}"

host_seen=false
container_seen=false
if grep -qi "${DELTA10_USB_ID}" <<<"${host_usb}"; then
  host_seen=true
fi
if grep -qi "${DELTA10_USB_ID}" <<<"${container_usb}"; then
  container_seen=true
fi

printf '\nDELTA10 (%s): host=%s container=%s\n' \
  "${DELTA10_USB_ID}" "${host_seen}" "${container_seen}"

if [ "${host_seen}" != true ] || [ "${container_seen}" != true ]; then
  echo "DELTA10 was not visible on both the host and in the NRV container." >&2
  exit 1
fi
