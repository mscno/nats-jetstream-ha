#!/bin/sh

set -eu
umask 077

require_env() {
  var_name="$1"
  eval "var_value=\${$var_name-}"
  if [ -z "$var_value" ]; then
    echo "error: environment variable $var_name is required" >&2
    exit 1
  fi
}

escape_nats_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_pem_file() {
  file_path="$1"
  file_contents="$2"
  printf '%s\n' "$file_contents" > "$file_path"
}

SERVER_NAME="${SERVER_NAME-}"
NATS_HOST="${NATS_HOST-0.0.0.0}"
NATS_PORT="${NATS_PORT-4222}"
NATS_HTTP_PORT="${NATS_HTTP_PORT-8222}"
NATS_AUTH_TOKEN="${NATS_AUTH_TOKEN-}"
NATS_CLUSTER_LISTEN="${NATS_CLUSTER_LISTEN-0.0.0.0:6222}"
NATS_CLUSTER_AUTH_USER="${NATS_CLUSTER_AUTH_USER-}"
NATS_CLUSTER_AUTH_PASSWORD="${NATS_CLUSTER_AUTH_PASSWORD-}"
JETSTREAM_STORE_DIR="${JETSTREAM_STORE_DIR-/data/jetstream}"
CLUSTER_NAME="${CLUSTER_NAME-cluster}"
CLUSTER_ROUTES_SEED_PRIMARY="${CLUSTER_ROUTES_SEED_PRIMARY-}"
CLUSTER_ROUTES_SEED_SECONDARY="${CLUSTER_ROUTES_SEED_SECONDARY-}"
NATS_TLS_CA_CERT_PEM="${NATS_TLS_CA_CERT_PEM-}"
NATS_TLS_CA_KEY_PEM="${NATS_TLS_CA_KEY_PEM-}"
RAILWAY_PRIVATE_DOMAIN="${RAILWAY_PRIVATE_DOMAIN-}"

require_env SERVER_NAME
require_env NATS_AUTH_TOKEN
require_env NATS_CLUSTER_AUTH_USER
require_env NATS_CLUSTER_AUTH_PASSWORD
require_env CLUSTER_ROUTES_SEED_PRIMARY
require_env CLUSTER_ROUTES_SEED_SECONDARY

SERVER_NAME_ESCAPED="$(escape_nats_string "$SERVER_NAME")"
NATS_HOST_ESCAPED="$(escape_nats_string "$NATS_HOST")"
NATS_AUTH_TOKEN_ESCAPED="$(escape_nats_string "$NATS_AUTH_TOKEN")"
JETSTREAM_STORE_DIR_ESCAPED="$(escape_nats_string "$JETSTREAM_STORE_DIR")"
CLUSTER_NAME_ESCAPED="$(escape_nats_string "$CLUSTER_NAME")"
NATS_CLUSTER_LISTEN_ESCAPED="$(escape_nats_string "$NATS_CLUSTER_LISTEN")"
NATS_CLUSTER_AUTH_USER_ESCAPED="$(escape_nats_string "$NATS_CLUSTER_AUTH_USER")"
NATS_CLUSTER_AUTH_PASSWORD_ESCAPED="$(escape_nats_string "$NATS_CLUSTER_AUTH_PASSWORD")"
CLUSTER_ROUTES_SEED_PRIMARY_ESCAPED="$(escape_nats_string "$CLUSTER_ROUTES_SEED_PRIMARY")"
CLUSTER_ROUTES_SEED_SECONDARY_ESCAPED="$(escape_nats_string "$CLUSTER_ROUTES_SEED_SECONDARY")"

CLIENT_ADVERTISE_LINE=""
CLUSTER_ADVERTISE_LINE=""
CLIENT_TLS_BLOCK=""
CLUSTER_TLS_BLOCK=""

if [ -n "$NATS_TLS_CA_CERT_PEM" ] || [ -n "$NATS_TLS_CA_KEY_PEM" ]; then
  require_env NATS_TLS_CA_CERT_PEM
  require_env NATS_TLS_CA_KEY_PEM
  require_env RAILWAY_PRIVATE_DOMAIN
  if ! command -v openssl >/dev/null 2>&1; then
    echo "error: openssl is required for automatic TLS certificate generation" >&2
    exit 1
  fi

  tls_dir="$(mktemp -d /tmp/nats-tls.XXXXXX)"
  ca_cert_path="$tls_dir/ca.pem"
  ca_key_path="$tls_dir/ca.key"
  leaf_key_path="$tls_dir/server-key.pem"
  leaf_csr_path="$tls_dir/server.csr"
  leaf_cert_path="$tls_dir/server-cert.pem"
  ext_path="$tls_dir/ext.cnf"

  write_pem_file "$ca_cert_path" "$NATS_TLS_CA_CERT_PEM"
  write_pem_file "$ca_key_path" "$NATS_TLS_CA_KEY_PEM"

  cat > "$ext_path" <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $RAILWAY_PRIVATE_DOMAIN
DNS.2 = $SERVER_NAME
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

  openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$leaf_key_path" \
    -out "$leaf_csr_path" \
    -subj "/CN=$RAILWAY_PRIVATE_DOMAIN" >/dev/null 2>&1

  openssl x509 \
    -req \
    -in "$leaf_csr_path" \
    -CA "$ca_cert_path" \
    -CAkey "$ca_key_path" \
    -CAcreateserial \
    -out "$leaf_cert_path" \
    -days 365 \
    -sha256 \
    -extfile "$ext_path" \
    -extensions v3_req >/dev/null 2>&1

  rm -f "$ca_key_path" "$leaf_csr_path" "$tls_dir/ca.srl"

  client_advertise="${RAILWAY_PRIVATE_DOMAIN}:${NATS_PORT}"
  cluster_advertise="${RAILWAY_PRIVATE_DOMAIN}:${NATS_CLUSTER_LISTEN##*:}"
  client_advertise_escaped="$(escape_nats_string "$client_advertise")"
  cluster_advertise_escaped="$(escape_nats_string "$cluster_advertise")"
  ca_cert_path_escaped="$(escape_nats_string "$ca_cert_path")"
  leaf_key_path_escaped="$(escape_nats_string "$leaf_key_path")"
  leaf_cert_path_escaped="$(escape_nats_string "$leaf_cert_path")"

  CLIENT_ADVERTISE_LINE="client_advertise: \"$client_advertise_escaped\""
  CLUSTER_ADVERTISE_LINE="  advertise: \"$cluster_advertise_escaped\""
  CLIENT_TLS_BLOCK=$(cat <<EOF
tls {
  cert_file: "$leaf_cert_path_escaped"
  key_file: "$leaf_key_path_escaped"
  ca_file: "$ca_cert_path_escaped"
  min_version: "1.2"
}
EOF
)
  CLUSTER_TLS_BLOCK=$(cat <<EOF
  tls {
    cert_file: "$leaf_cert_path_escaped"
    key_file: "$leaf_key_path_escaped"
    ca_file: "$ca_cert_path_escaped"
    min_version: "1.2"
    verify_cert_and_check_known_urls: true
  }
EOF
)
fi

cat > /tmp/nats-server.conf <<EOF
server_name: "$SERVER_NAME_ESCAPED"

host: "$NATS_HOST_ESCAPED"
port: $NATS_PORT

http_port: $NATS_HTTP_PORT

$CLIENT_ADVERTISE_LINE

authorization {
  token: "$NATS_AUTH_TOKEN_ESCAPED"
}

$CLIENT_TLS_BLOCK

jetstream {
  store_dir: "$JETSTREAM_STORE_DIR_ESCAPED"
}

cluster {
  name: "$CLUSTER_NAME_ESCAPED"
  listen: "$NATS_CLUSTER_LISTEN_ESCAPED"
$CLUSTER_ADVERTISE_LINE
  authorization {
    user: "$NATS_CLUSTER_AUTH_USER_ESCAPED"
    password: "$NATS_CLUSTER_AUTH_PASSWORD_ESCAPED"
  }
$CLUSTER_TLS_BLOCK
  routes = [
    "$CLUSTER_ROUTES_SEED_PRIMARY_ESCAPED",
    "$CLUSTER_ROUTES_SEED_SECONDARY_ESCAPED"
  ]
}
EOF

nats_server_bin="${NATS_SERVER_BIN-}"
if [ -z "$nats_server_bin" ]; then
  nats_server_bin="$(command -v nats-server || true)"
fi
if [ -z "$nats_server_bin" ]; then
  echo "error: could not find nats-server in PATH" >&2
  exit 1
fi

exec "$nats_server_bin" --config /tmp/nats-server.conf
