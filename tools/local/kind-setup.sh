#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-arlo-local}"
FORCE_RECREATE=0

usage() {
  cat <<USAGE
Usage: $0 [--force-recreate]

Creates/refreshes a KinD cluster with ingress, Argo CD (local values), and External Secrets
with a fake SecretStore suitable for offline smoke tests.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-recreate)
      FORCE_RECREATE=1
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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kind
require_cmd kubectl
require_cmd helm

KUBE_CTX="kind-${CLUSTER_NAME}"

if [[ ${FORCE_RECREATE} -eq 1 ]]; then
  if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "[kind] deleting existing cluster ${CLUSTER_NAME}"
    kind delete cluster --name "${CLUSTER_NAME}"
  fi
fi

if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "[kind] creating cluster ${CLUSTER_NAME}"
  cat <<'CFG' | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
CFG
else
  echo "[kind] cluster ${CLUSTER_NAME} already exists"
fi

kubectl --context "${KUBE_CTX}" wait --for=condition=Ready nodes --all --timeout=120s

# Ingress controller
if ! kubectl --context "${KUBE_CTX}" get ns ingress-nginx >/dev/null 2>&1; then
  echo "[ingress] installing ingress-nginx"
  kubectl --context "${KUBE_CTX}" apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  kubectl --context "${KUBE_CTX}" wait -n ingress-nginx --for=condition=Available deploy/ingress-nginx-controller --timeout=180s
else
  echo "[ingress] ingress-nginx already present"
fi

# Argo CD with local values
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f "${ROOT_DIR}/ci-cd/argocd/local-values.yaml"

kubectl --context "${KUBE_CTX}" rollout status deploy/argocd-server -n argocd --timeout=180s

# External Secrets with fake SecretStore
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update >/dev/null

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true \
  --set metrics.enabled=false

kubectl --context "${KUBE_CTX}" rollout status deploy/external-secrets -n external-secrets --timeout=180s

# Kustomize dry-run & apply for local overlay
echo "[k8s] server-side dry-run for kubernetes/overlays/local"
kubectl --context "${KUBE_CTX}" apply --server-side --dry-run=server -k "${ROOT_DIR}/kubernetes/overlays/local"

echo "[k8s] applying kubernetes/overlays/local"
kubectl --context "${KUBE_CTX}" apply -k "${ROOT_DIR}/kubernetes/overlays/local"

kubectl --context "${KUBE_CTX}" rollout status deploy/arlo-demo-app -n api --timeout=180s

cat <<NOTE
KinD cluster '${CLUSTER_NAME}' is ready.
- Ingress forwards api.arlo-resilience.com -> http://127.0.0.1:8080
- Argo CD available inside cluster at service argocd-server.argocd.svc
- External Secrets fake store seeded for offline flows
NOTE
