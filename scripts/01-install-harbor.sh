#!/usr/bin/env bash
# Install Harbor with a self-signed certificate using the official online installer.
# Run as root on the node that will host the registry.
#
# Usage:
#   HARBOR_ADMIN_PASSWORD='...' HARBOR_DB_PASSWORD='...' ./01-install-harbor.sh
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-192.168.1.5}"
HARBOR_VERSION="${HARBOR_VERSION:-v2.12.1}"
INSTALL_DIR="${INSTALL_DIR:-/opt/harbor}"
CERT_DIR="${CERT_DIR:-/etc/harbor/certs}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:?set HARBOR_ADMIN_PASSWORD}"
HARBOR_DB_PASSWORD="${HARBOR_DB_PASSWORD:?set HARBOR_DB_PASSWORD}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARBALL="harbor-online-installer-${HARBOR_VERSION}.tgz"
URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${TARBALL}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null || { echo "docker compose plugin is required" >&2; exit 1; }

echo "==> Generating TLS certificate for ${HARBOR_HOST}"
HARBOR_HOST="${HARBOR_HOST}" CERT_DIR="${CERT_DIR}" "${REPO_ROOT}/manifests/harbor/generate-cert.sh"

echo "==> Downloading Harbor ${HARBOR_VERSION} into ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
if [[ ! -x "${INSTALL_DIR}/install.sh" ]]; then
  curl -fsSL -o "/tmp/${TARBALL}" "${URL}"
  tar xzf "/tmp/${TARBALL}" -C "${INSTALL_DIR}" --strip-components=1
  rm -f "/tmp/${TARBALL}"
fi

echo "==> Rendering harbor.yml"
if [[ -f "${INSTALL_DIR}/harbor.yml" ]]; then
  echo "    ${INSTALL_DIR}/harbor.yml already exists, leaving it untouched."
else
  sed -e "s|^hostname: .*|hostname: ${HARBOR_HOST}|" \
      -e "s|<HARBOR_ADMIN_PASSWORD>|${HARBOR_ADMIN_PASSWORD}|" \
      -e "s|<DB_PASSWORD>|${HARBOR_DB_PASSWORD}|" \
      -e "s|/etc/harbor/certs|${CERT_DIR}|g" \
      "${REPO_ROOT}/manifests/harbor/harbor.yml.example" > "${INSTALL_DIR}/harbor.yml"
  chmod 600 "${INSTALL_DIR}/harbor.yml"
fi

echo "==> Running the Harbor installer"
(cd "${INSTALL_DIR}" && ./install.sh)

echo "==> Waiting for Harbor to become healthy"
for _ in $(seq 1 60); do
  code="$(curl -k -s -o /dev/null -w '%{http_code}' "https://${HARBOR_HOST}/api/v2.0/health" || true)"
  [[ "${code}" == "200" ]] && break
  sleep 5
done
curl -k -s "https://${HARBOR_HOST}/api/v2.0/health"; echo

cat <<EOF

Harbor is running at https://${HARBOR_HOST} (user: admin).
Next:
  1. scripts/02-trust-harbor-ca.sh ${CERT_DIR}/harbor.crt     (on every node)
  2. Create project "client-demo" and a robot account in the UI.
EOF
