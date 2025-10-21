#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${1:-api.arlo-resilience.com}"
LOCAL_MODE="${LOCAL_MODE:-0}"
SCHEME="https"

if [[ "${LOCAL_MODE}" == "1" ]]; then
  SCHEME="${SMOKE_SCHEME:-http}"
fi

read -r -a SMOKE_EXTRA_ARGS <<< "${SMOKE_CURL_OPTS:-}"

if ! command -v curl >/dev/null; then
  echo "curl not available" >&2
  exit 1
fi

printf 'Running smoke test against %s\n' "${TARGET_HOST}"

STATUS=$(curl "${SMOKE_EXTRA_ARGS[@]}" -s -o /tmp/arlo-smoke-response -w '%{http_code}' "${SCHEME}://${TARGET_HOST}/health")

if [[ "${STATUS}" -ne 200 ]]; then
  echo "Health check failed with status ${STATUS}" >&2
  cat /tmp/arlo-smoke-response >&2
  exit 1
fi

echo "AWS cluster response:"
cat /tmp/arlo-smoke-response

if command -v dig >/dev/null; then
  echo "Checking DNS fail-over order"
  dig +short "${TARGET_HOST}"
fi

rm -f /tmp/arlo-smoke-response

echo "Smoke test succeeded"
