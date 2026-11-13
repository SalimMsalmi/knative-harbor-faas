#!/usr/bin/env bash
# Invoke a deployed function through the Kourier NodePort.
#
# Usage: ./invoke.sh <service-name> [payload]
#   ./invoke.sh tfunction '{"numbers": [3, 1, 4]}'
set -euo pipefail

NAME="${1:?usage: $0 <service-name> [payload]}"
PAYLOAD="${2:-}"
NAMESPACE="${NAMESPACE:-default}"
NODE_IP="${NODE_IP:-192.168.1.5}"
KOURIER_NODEPORT="${KOURIER_NODEPORT:-32491}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-${NODE_IP}.sslip.io}"

curl -sS \
  -H "Host: ${NAME}.${NAMESPACE}.${DOMAIN_SUFFIX}" \
  -H "Content-Type: application/json" \
  --data-raw "${PAYLOAD}" \
  "http://${NODE_IP}:${KOURIER_NODEPORT}"
echo
