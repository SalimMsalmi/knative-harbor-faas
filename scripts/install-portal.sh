#!/usr/bin/env bash
# Install the FaaS portal as a systemd service on the build host (master node).
# Run as root.
#
# Usage: sudo ./install-portal.sh
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/faas-portal}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for bin in python3 docker kubectl; do
  command -v "${bin}" >/dev/null || { echo "${bin} is required" >&2; exit 1; }
done

echo "==> Copying portal to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/builds"
cp "${REPO_ROOT}/portal/app.py" "${INSTALL_DIR}/"
cp -r "${REPO_ROOT}/portal/static" "${REPO_ROOT}/portal/templates" "${INSTALL_DIR}/"

echo "==> Installing Python dependencies"
python3 -m pip install -r "${REPO_ROOT}/portal/requirements.txt"

echo "==> Installing systemd unit"
sed "s|/opt/faas-portal|${INSTALL_DIR}|g" "${REPO_ROOT}/manifests/faas-portal.service" \
  > /etc/systemd/system/faas-portal.service
systemctl daemon-reload
systemctl enable --now faas-portal

sleep 2
systemctl --no-pager status faas-portal | head -5
echo
echo "Portal: http://$(hostname -I | awk '{print $1}'):${PORTAL_PORT:-5000}"
