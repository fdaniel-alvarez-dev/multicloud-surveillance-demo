#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_DIR="${ROOT_DIR}/terraform/environments"
SILENT=0

usage() {
  cat <<USAGE
Usage: $0 [--silent]

Generates local Terraform plans for every environment with safe defaults:
  - backend disabled
  - refresh disabled
  - lock disabled
  - TF_VAR_use_mock defaults to true
  - plan outputs stored as plan.out and plan.json
USAGE
}

log() {
  if [[ ${SILENT} -eq 0 ]]; then
    echo "$*"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --silent)
      SILENT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd terraform

export TF_VAR_use_mock="${TF_VAR_use_mock:-true}"

for env in "${ENV_DIR}"/*; do
  [[ -d "${env}" ]] || continue
  rel_path="${env#${ROOT_DIR}/}"
  plan_path="${env}/plan.out"
  json_path="${env}/plan.json"

  log "[plan] ${rel_path}"
  (cd "${env}" && terraform init -backend=false -input=false >/dev/null)
  (cd "${env}" && terraform plan -lock=false -refresh=false -input=false -out=plan.out)
  (cd "${env}" && terraform show -json plan.out > plan.json)
  log "[plan] produced ${json_path#${ROOT_DIR}/}"

done

log "All local plans finished."
