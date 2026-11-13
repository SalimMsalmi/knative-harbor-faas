#!/usr/bin/env bash
# Build a function image and push it to Harbor.
#
# Usage: ./build-push.sh <function-dir> [image-name]
#   ./build-push.sh functions/number-stats tfunction
#
# A directory containing only handler.py is built with the portal runtime
# template. A directory with its own Dockerfile (functions/hello-client) is
# built as-is.
set -euo pipefail

FUNC_DIR="${1:?usage: $0 <function-dir> [image-name]}"
NAME="${2:-$(basename "${FUNC_DIR}")}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-192.168.1.5}"
HARBOR_PROJECT="${HARBOR_PROJECT:-client-demo}"
TAG="${TAG:-latest}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/portal/templates}"
IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${NAME}:${TAG}"

[[ -d "${FUNC_DIR}" ]] || { echo "no such directory: ${FUNC_DIR}" >&2; exit 1; }

if [[ -f "${FUNC_DIR}/Dockerfile" ]]; then
  CONTEXT="${FUNC_DIR}"
else
  [[ -f "${FUNC_DIR}/handler.py" ]] || { echo "${FUNC_DIR}/handler.py not found" >&2; exit 1; }
  CONTEXT="$(mktemp -d)"
  trap 'rm -rf "${CONTEXT}"' EXIT
  cp "${TEMPLATE_DIR}/Dockerfile" "${TEMPLATE_DIR}/index.py" "${TEMPLATE_DIR}/requirements.txt" "${CONTEXT}/"
  mkdir -p "${CONTEXT}/function"
  cp "${FUNC_DIR}/handler.py" "${CONTEXT}/function/handler.py"
fi

echo "==> Building ${IMAGE}"
docker build -t "${IMAGE}" "${CONTEXT}"

echo "==> Pushing ${IMAGE}"
docker push "${IMAGE}"

echo "Pushed ${IMAGE}"
