#!/usr/bin/env bash
set -euo pipefail

AWS_CONTEXT="${1:-arn:aws:eks:us-east-1:741852963000:cluster/arlo-eks-cluster}"
GCP_ENDPOINT="${2:-https://api.arlo-resilience.com}"
AWS_NAMESPACE="${AWS_NAMESPACE:-api}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-arlo-demo-app}"

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

if ! command -v kubectl >/dev/null; then
  echo "kubectl is required" >&2
  exit 1
fi

log "Switching kubectl context to ${AWS_CONTEXT}"
kubectl config use-context "${AWS_CONTEXT}" >/dev/null

log "Scaling down deployment ${DEPLOYMENT_NAME} in namespace ${AWS_NAMESPACE}"
kubectl scale deployment "${DEPLOYMENT_NAME}" -n "${AWS_NAMESPACE}" --replicas=0

log "Waiting for pods to terminate"
for _ in {1..12}; do
  running=$(kubectl get pods -n "${AWS_NAMESPACE}" -l app.kubernetes.io/name="${DEPLOYMENT_NAME}" --no-headers 2>/dev/null | wc -l)
  if [[ "${running}" -eq 0 ]]; then
    break
  fi
  sleep 10
done

log "Triggering health check against ${GCP_ENDPOINT}/health"
if command -v curl >/dev/null; then
  curl -fsSL "${GCP_ENDPOINT}/health" || true
fi

log "Failover simulation complete. Monitor Route 53 and Cloud DNS for traffic shift."
