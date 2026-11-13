#!/usr/bin/env bash
# Generate a self-signed TLS certificate for Harbor with an IP SAN.
#
# Usage: HARBOR_HOST=192.168.1.5 CERT_DIR=/etc/harbor/certs ./generate-cert.sh
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-192.168.1.5}"
CERT_DIR="${CERT_DIR:-/etc/harbor/certs}"
DAYS="${DAYS:-3650}"

mkdir -p "${CERT_DIR}"
cd "${CERT_DIR}"

if [[ -f harbor.crt && -f harbor.key ]]; then
  echo "Certificate already exists in ${CERT_DIR}, leaving it untouched."
  exit 0
fi

cat > openssl.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3_req
prompt             = no
[dn]
C  = TN
O  = knative-harbor-faas
CN = ${HARBOR_HOST}
[v3_req]
basicConstraints = CA:TRUE
keyUsage         = digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names
[alt_names]
IP.1  = ${HARBOR_HOST}
DNS.1 = ${HARBOR_HOST}
EOF

openssl req -x509 -nodes -newkey rsa:4096 -sha256 -days "${DAYS}" \
  -keyout harbor.key -out harbor.crt -config openssl.cnf

chmod 600 harbor.key
chmod 644 harbor.crt
rm -f openssl.cnf

echo "Generated:"
openssl x509 -in harbor.crt -noout -subject -ext subjectAltName -enddate
