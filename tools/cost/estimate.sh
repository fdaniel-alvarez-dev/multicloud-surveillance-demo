#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_DIR="${ROOT_DIR}/terraform/environments"
MAX_DELTA="${MAX_MONTHLY_DELTA:-50}"
TMP_OUTPUT="$(mktemp)"
trap 'rm -f "${TMP_OUTPUT}"' EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd infracost
require_cmd jq
require_cmd terraform

# Ensure plans exist.
"${ROOT_DIR}/tools/terraform/plan_local.sh" --silent >/dev/null

total_delta="0"

for env in "${ENV_DIR}"/*; do
  [[ -d "${env}" ]] || continue
  rel_path="${env#${ROOT_DIR}/}"
  plan_json="${env}/plan.json"
  if [[ ! -f "${plan_json}" ]]; then
    echo "Plan JSON missing for ${rel_path}. Run plan_local.sh first." >&2
    exit 1
  fi

  echo "[cost] infracost breakdown -> ${rel_path}"
  infracost breakdown \
    --path "${env}" \
    --config-file "${ROOT_DIR}/tools/cost/infracost.toml" \
    --terraform-plan-file "${plan_json}" \
    --usage-file "${ROOT_DIR}/tools/cost/usage.yml" \
    --no-color \
    --skip-update-check \
    --format json > "${TMP_OUTPUT}"

  delta=$(jq -r '[.projects[].breakdown.diffTotalMonthlyCost] | add // 0' "${TMP_OUTPUT}")
  echo "[cost] delta for ${rel_path}: $${delta:-0} per month"
  total_delta=$(python3 - <<PY
from decimal import Decimal
print(Decimal("${total_delta}") + Decimal(str(${delta})))
PY
)
done

threshold=$(python3 - <<PY
from decimal import Decimal
print(Decimal("${MAX_DELTA}"))
PY
)

printf '[cost] combined delta: $%s/mo (threshold $%s/mo)\n' "${total_delta}" "${threshold}"

python3 - <<PY
from decimal import Decimal
if Decimal("${total_delta}") > Decimal("${threshold}"):
    raise SystemExit("Estimated monthly delta exceeds MAX_MONTHLY_DELTA")
PY

echo "[cost] OK"
