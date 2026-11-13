#!/usr/bin/env bash
# Install Knative Serving and Kourier, configured for a private self-signed registry.
#
# Usage: ./03-install-knative.sh
set -euo pipefail

KNATIVE_VERSION="${KNATIVE_VERSION:-1.16.0}"
HARBOR_HOST="${HARBOR_HOST:-192.168.1.5}"
DOMAIN="${DOMAIN:-${HARBOR_HOST}.sslip.io}"

SERVING="https://github.com/knative/serving/releases/download/knative-v${KNATIVE_VERSION}"
KOURIER="https://github.com/knative/net-kourier/releases/download/knative-v${KNATIVE_VERSION}"

echo "==> Knative Serving ${KNATIVE_VERSION}: CRDs"
kubectl apply -f "${SERVING}/serving-crds.yaml"
kubectl wait --for=condition=Established --all crd --timeout=120s

echo "==> Knative Serving ${KNATIVE_VERSION}: core"
kubectl apply -f "${SERVING}/serving-core.yaml"

echo "==> Kourier ${KNATIVE_VERSION}"
kubectl apply -f "${KOURIER}/kourier.yaml"

echo "==> Configuring ingress class, domain and tag resolution"
kubectl patch configmap/config-network -n knative-serving --type merge \
  -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
kubectl patch configmap/config-domain -n knative-serving --type merge \
  -p "{\"data\":{\"${DOMAIN}\":\"\"}}"
kubectl patch configmap/config-deployment -n knative-serving --type merge \
  -p "{\"data\":{\"registries-skipping-tag-resolving\":\"${HARBOR_HOST}\"}}"

echo "==> Waiting for the control plane"
kubectl rollout restart deployment/controller -n knative-serving
kubectl wait --for=condition=Available deployment --all -n knative-serving --timeout=300s
kubectl wait --for=condition=Available deployment --all -n kourier-system --timeout=300s

echo
kubectl get pods -n knative-serving
echo
kubectl get svc kourier -n kourier-system
NODEPORT="$(kubectl get svc kourier -n kourier-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"
echo
echo "Kourier HTTP NodePort: ${NODEPORT}  (export KOURIER_NODEPORT=${NODEPORT})"
