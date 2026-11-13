#!/usr/bin/env bash
# Apply a function's Knative Service and wait until it is Ready.
#
# Usage: ./deploy.sh <function-directory-name>
#   ./deploy.sh number-stats        # applies functions/number-stats/service.yaml
set -euo pipefail

FUNC="${1:?usage: $0 <function-directory-name>}"
TIMEOUT="${TIMEOUT:-120s}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${REPO_ROOT}/functions/${FUNC}/service.yaml"

[[ -f "${MANIFEST}" ]] || { echo "manifest not found: ${MANIFEST}" >&2; exit 1; }

NAME="$(kubectl apply -f "${MANIFEST}" -o jsonpath='{.metadata.name}')"
NAMESPACE="$(kubectl apply --dry-run=client -f "${MANIFEST}" -o jsonpath='{.metadata.namespace}')"
NAMESPACE="${NAMESPACE:-default}"

echo "==> Waiting for ksvc/${NAME} to become Ready (timeout ${TIMEOUT})"
if ! kubectl wait ksvc "${NAME}" -n "${NAMESPACE}" --for=condition=Ready --timeout="${TIMEOUT}"; then
  kubectl get ksvc "${NAME}" -n "${NAMESPACE}"
  kubectl get pods -n "${NAMESPACE}" -l "serving.knative.dev/service=${NAME}"
  exit 1
fi

kubectl get ksvc "${NAME}" -n "${NAMESPACE}"
