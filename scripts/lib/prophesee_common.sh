#!/usr/bin/env bash

set -euo pipefail

kv_value() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}'
}

require_safe_prefix() {
  local value="$1"
  if [[ ! "${value}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Prefix may contain only letters, digits, dot, underscore, and dash: ${value}" >&2
    exit 1
  fi
}

to_container_path() {
  local value="$1"
  case "${value}" in
    /workspace/*)
      printf '%s\n' "${value}"
      ;;
    "${PROJECT_ROOT}"/*)
      printf '/workspace/%s\n' "${value#${PROJECT_ROOT}/}"
      ;;
    *)
      echo "Path must be inside ${PROJECT_ROOT} or /workspace: ${value}" >&2
      exit 1
      ;;
  esac
}

project_git() {
  if [ "$(id -u)" -eq 0 ]; then
    sudo -u developer git -C /workspace "$@"
  else
    git -C /workspace "$@"
  fi
}

project_commit() {
  project_git rev-parse HEAD 2>/dev/null || printf 'unknown\n'
}

project_dirty() {
  if project_git diff --quiet --ignore-submodules -- && \
     [ -z "$(project_git ls-files --others --exclude-standard)" ]; then
    printf 'false\n'
  else
    printf 'true\n'
  fi
}

calibration_sha() {
  local serial="$1"
  local calibration="/workspace/config/camera_info/prophesee_${serial}.yaml"
  if [ -f "${calibration}" ]; then
    sha256sum "${calibration}" | awk '{print $1}'
  else
    printf 'none\n'
  fi
}
