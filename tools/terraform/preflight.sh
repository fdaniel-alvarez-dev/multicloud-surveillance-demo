#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_DIR="${ROOT_DIR}/terraform/environments"
STAGE="${1:-static}"

usage() {
  cat <<USAGE
Usage: $0 [static|policy|all]

  static - run fmt-check, tflint, tfsec, checkov, terraform validate
  policy - ensure plan.json exists (mocked) and run conftest policies
  all    - run both static and policy stages
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

run_static() {
  echo "[terraform] fmt -check"
  (cd "${ROOT_DIR}" && terraform fmt -check -recursive)

  echo "[terraform] tflint"
  (cd "${ROOT_DIR}" && tflint --recursive)

  echo "[terraform] tfsec --soft-fail"
  (cd "${ROOT_DIR}" && tfsec --soft-fail)

  echo "[terraform] checkov -s"
  (cd "${ROOT_DIR}" && checkov -s --framework terraform)

  for env in "${ENV_DIR}"/*; do
    [ -d "${env}" ] || continue
    echo "[terraform] init/validate -> ${env#${ROOT_DIR}/}"
    (cd "${env}" && terraform init -backend=false -input=false >/dev/null)
    (cd "${env}" && terraform validate)
  done
}

run_policy() {
  echo "[policy] generating plan.json for each environment"
  TF_VAR_use_mock=${TF_VAR_use_mock:-true} "${ROOT_DIR}/tools/terraform/plan_local.sh" --silent

  for env in "${ENV_DIR}"/*; do
    [ -d "${env}" ] || continue
    plan_json="${env}/plan.json"
    if [ ! -f "${plan_json}" ]; then
      echo "Plan JSON missing for ${env}." >&2
      exit 1
    fi
    echo "[policy] conftest -> ${plan_json#${ROOT_DIR}/}"
    conftest test -p "${ROOT_DIR}/policy/opa" "${plan_json}"
  done
}

case "${STAGE}" in
  static)
    require_cmd terraform
    require_cmd tflint
    require_cmd tfsec
    require_cmd checkov
    run_static
    ;;
  policy)
    require_cmd terraform
    require_cmd conftest
    run_policy
    ;;
  all)
    require_cmd terraform
    require_cmd tflint
    require_cmd tfsec
    require_cmd checkov
    require_cmd conftest
    run_static
    run_policy
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown stage: ${STAGE}" >&2
    usage
    exit 1
    ;;

esac
