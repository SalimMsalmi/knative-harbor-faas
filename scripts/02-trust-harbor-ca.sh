#!/usr/bin/env bash
# Make this node trust the Harbor self-signed certificate.
# Run as root on EVERY Kubernetes node (control plane and workers).
#
# Usage: ./02-trust-harbor-ca.sh /path/to/harbor.crt
set -euo pipefail

CA_FILE="${1:?usage: $0 /path/to/harbor.crt}"
HARBOR_HOST="${HARBOR_HOST:-192.168.1.5}"
CERTS_D="/etc/containerd/certs.d"
CONTAINERD_CONFIG="/etc/containerd/config.toml"

[[ -f "${CA_FILE}" ]] || { echo "certificate not found: ${CA_FILE}" >&2; exit 1; }

echo "==> containerd: ${CERTS_D}/${HARBOR_HOST}"
mkdir -p "${CERTS_D}/${HARBOR_HOST}"
cp "${CA_FILE}" "${CERTS_D}/${HARBOR_HOST}/ca.crt"
cat > "${CERTS_D}/${HARBOR_HOST}/hosts.toml" <<EOF
server = "https://${HARBOR_HOST}"

[host."https://${HARBOR_HOST}"]
  capabilities = ["pull", "resolve", "push"]
  ca = "${CERTS_D}/${HARBOR_HOST}/ca.crt"
  skip_verify = false
EOF

# containerd only reads certs.d when the CRI registry config_path is set.
if [[ -f "${CONTAINERD_CONFIG}" ]] && ! grep -Eq "^\s*config_path\s*=\s*['\"][^'\"]*certs\.d" "${CONTAINERD_CONFIG}"; then
  echo "==> containerd: registry config_path does not reference certs.d"
  echo "    Set it in ${CONTAINERD_CONFIG} under the CRI registry section, e.g.:"
  echo "      config_path = '${CERTS_D}:/etc/docker/certs.d'"
  echo "    then: systemctl restart containerd"
fi

if command -v docker >/dev/null 2>&1; then
  echo "==> docker: /etc/docker/certs.d/${HARBOR_HOST}"
  mkdir -p "/etc/docker/certs.d/${HARBOR_HOST}"
  cp "${CA_FILE}" "/etc/docker/certs.d/${HARBOR_HOST}/ca.crt"
fi

echo "==> system trust store"
cp "${CA_FILE}" /usr/local/share/ca-certificates/harbor-registry.crt
update-ca-certificates >/dev/null

echo "==> restarting containerd"
systemctl restart containerd

echo "Done. Verify with:"
echo "  curl https://${HARBOR_HOST}/api/v2.0/health"
