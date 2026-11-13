#!/usr/bin/env bash
# Create the imagePullSecret that every Knative Service references.
# The robot token comes from Harbor: Projects -> client-demo -> Robot Accounts.
#
# Usage: ROBOT_TOKEN='<ROBOT_TOKEN>' ./image-pull-secret.example.sh
set -euo pipefail

HARBOR_REGISTRY="${HARBOR_REGISTRY:-192.168.1.5}"
HARBOR_PROJECT="${HARBOR_PROJECT:-client-demo}"
ROBOT_USER="${ROBOT_USER:-robot\$${HARBOR_PROJECT}+${HARBOR_PROJECT}-robot}"
ROBOT_TOKEN="${ROBOT_TOKEN:?set ROBOT_TOKEN to the Harbor robot account secret}"
SECRET_NAME="${SECRET_NAME:-harbor-registry}"
NAMESPACE="${NAMESPACE:-default}"

kubectl create secret docker-registry "${SECRET_NAME}" \
  --docker-server="${HARBOR_REGISTRY}" \
  --docker-username="${ROBOT_USER}" \
  --docker-password="${ROBOT_TOKEN}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}"
