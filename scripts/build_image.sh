#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

compose build "${SERVICE_NAME}"
