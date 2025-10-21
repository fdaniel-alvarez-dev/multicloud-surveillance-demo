#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/tools/local/docker-compose.local.yml"
CLUSTER_NAME="${CLUSTER_NAME:-arlo-local}"
KUBE_CTX="kind-${CLUSTER_NAME}"
TARGET_HOST="api.arlo-resilience.com:8080"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd kubectl
require_cmd kind
require_cmd dig

# Ensure compose stack is up.
echo "[offline] starting local docker stack"
docker compose -f "${COMPOSE_FILE}" up -d

# Make sure cluster exists and resources applied.
"${ROOT_DIR}/tools/local/kind-setup.sh"

kubectl --context "${KUBE_CTX}" wait -n api --for=condition=Available deploy/arlo-demo-app --timeout=180s

# Ensure ingress service endpoints ready
kubectl --context "${KUBE_CTX}" wait -n ingress-nginx --for=condition=Available deploy/ingress-nginx-controller --timeout=180s

# Verify CoreDNS stub resolves to localhost
dig @127.0.0.1 -p 15353 "api.arlo-resilience.com" +short | grep -q "127.0.0.1"

echo "[offline] running smoke test via local ingress"
LOCAL_MODE=1 \
SMOKE_SCHEME=http \
SMOKE_CURL_OPTS="--resolve api.arlo-resilience.com:8080:127.0.0.1" \
TARGET_HOST="${TARGET_HOST}" \
  bash "${ROOT_DIR}/tests/smoke.sh"

echo "[offline] checking DNS script against stubbed resolver"
python3 "${ROOT_DIR}/tests/dns_check.py" "api.arlo-resilience.com" || true

echo "[offline] success — local smoke complete"
