#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/nrv_viewer_common.sh"

check_nrv_viewer_source
prepare_nrv_data_directories
nrv_compose build "${NRV_SERVICE_NAME}"
