#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/nrv_viewer_common.sh"

prepare_nrv_data_directories
nrv_compose run --rm --entrypoint bash "${NRV_SERVICE_NAME}"
