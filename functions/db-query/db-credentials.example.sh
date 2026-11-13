#!/usr/bin/env bash
# Create the secret consumed by functions/db-query/service.yaml.
# Usage: DB_PASSWORD='<DB_PASSWORD>' ./db-credentials.example.sh
set -euo pipefail

DB_HOST="${DB_HOST:-192.168.1.7}"
DB_PASSWORD="${DB_PASSWORD:?set DB_PASSWORD}"
NAMESPACE="${NAMESPACE:-default}"

kubectl create secret generic db-credentials \
  --from-literal=host="${DB_HOST}" \
  --from-literal=password="${DB_PASSWORD}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -
