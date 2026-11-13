#!/usr/bin/env bash
# Measure cold-start and warm latency of a function.
# For each run: wait until the function has scaled to zero, send one request
# (cold), then three more (warm).
#
# Usage: ./cold-start-bench.sh <service-name> [runs]
set -euo pipefail

NAME="${1:?usage: $0 <service-name> [runs]}"
RUNS="${2:-3}"
NAMESPACE="${NAMESPACE:-default}"
NODE_IP="${NODE_IP:-192.168.1.5}"
KOURIER_NODEPORT="${KOURIER_NODEPORT:-32491}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-${NODE_IP}.sslip.io}"

HOST="Host: ${NAME}.${NAMESPACE}.${DOMAIN_SUFFIX}"
URL="http://${NODE_IP}:${KOURIER_NODEPORT}"
SELECTOR="serving.knative.dev/service=${NAME}"

request() {
  curl -s -o /dev/null -w '%{http_code} %{time_total}' -H "${HOST}" --data-raw 'ping' "${URL}"
}

wait_for_zero() {
  printf 'waiting for scale-to-zero'
  for _ in $(seq 1 60); do
    count="$(kubectl get pods -n "${NAMESPACE}" -l "${SELECTOR}" --no-headers 2>/dev/null | wc -l)"
    if [[ "${count}" -eq 0 ]]; then echo; return 0; fi
    printf '.'
    sleep 5
  done
  echo
  echo "function did not scale to zero within 5 minutes" >&2
  return 1
}

for run in $(seq 1 "${RUNS}"); do
  wait_for_zero
  read -r code total <<<"$(request)"
  echo "run ${run}: cold  HTTP ${code}  ${total}s"
  for _ in 1 2 3; do
    read -r code total <<<"$(request)"
    echo "run ${run}: warm  HTTP ${code}  ${total}s"
  done
done
