#!/bin/sh
# Generates the TLS fixtures of Tests/DcmSwiftTests/CIResources: test-only
# ECDSA P-256 keys and SHA-256 certificates, as PS3.15 B.13 requires.
# Needs OpenSSL 3.4 or later (-not_before, -not_after).
set -eu
out="${1:-$(dirname "$0")/../Tests/DcmSwiftTests/CIResources}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

key() { openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1" 2>/dev/null; }

ca() { # name subject
  key "$work/$1-key.pem"
  openssl req -x509 -new -key "$work/$1-key.pem" -sha256 -days 36500 -subj "$2" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$work/$1.pem"
}

leaf() { # name ca subject extensions [validity options]
  name=$1 issuer=$2 subject=$3 extensions=$4
  shift 4
  key "$work/$name-key.pem"
  openssl req -new -key "$work/$name-key.pem" -subj "$subject" -out "$work/$name.csr"
  printf '%s\n' "basicConstraints=CA:FALSE" "$extensions" | tr ';' '\n' > "$work/$name.ext"
  openssl x509 -req -in "$work/$name.csr" -CA "$work/$issuer.pem" -CAkey "$work/$issuer-key.pem" \
    -CAcreateserial -sha256 -extfile "$work/$name.ext" -out "$work/$name.pem" "$@" 2>/dev/null
}

ca tls-ca "/CN=DcmSwift Test CA"
ca tls-other-ca "/CN=DcmSwift Untrusted Test CA"
server="keyUsage=critical,digitalSignature;extendedKeyUsage=serverAuth"
client="keyUsage=critical,digitalSignature;extendedKeyUsage=clientAuth"
leaf tls-server tls-ca "/CN=DcmSwift Test Server" "$server;subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1" -days 36500
leaf tls-client tls-ca "/CN=DCMCLIENT" "$client" -days 36500
leaf tls-untrusted-client tls-other-ca "/CN=STRANGER" "$client" -days 36500
leaf tls-wrong-host tls-ca "/CN=other.example" "$server;subjectAltName=DNS:other.example" -days 36500
leaf tls-expired tls-ca "/CN=DcmSwift Expired Server" "$server;subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -not_before 20200101000000Z -not_after 20210101000000Z

cp "$work/tls-ca.pem" "$work/tls-other-ca.pem" "$out/"
for name in tls-server tls-client tls-untrusted-client tls-wrong-host tls-expired; do
  cp "$work/$name.pem" "$work/$name-key.pem" "$out/"
done
echo "TLS fixtures written to $out"
