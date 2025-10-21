#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBE_DIR="${ROOT_DIR}/kubernetes/overlays"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kustomize
require_cmd kubeconform
require_cmd kubectl

deploy_overlay() {
  local overlay=$1
  local output="${TMP_DIR}/${overlay}.yaml"
  local overlay_dir="${KUBE_DIR}/${overlay}"
  if [[ ! -d "${overlay_dir}" ]]; then
    echo "Missing overlay ${overlay_dir}" >&2
    exit 1
  fi

  echo "[k8s] rendering ${overlay_dir}"
  kustomize build "${overlay_dir}" > "${output}"

  echo "[k8s] kubeconform ${overlay}"
  kubeconform -summary "${output}"

  echo "[k8s] kubectl apply --dry-run=server ${overlay}"
  kubectl apply --server-side --dry-run=server -f "${output}"

  echo "[k8s] kubectl diff ${overlay}"
  kubectl diff -f "${output}"
}

deploy_overlay aws
deploy_overlay gcp

echo "[k8s] validation complete"
