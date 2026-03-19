#!/bin/sh

set -eu

require_env() {
  var_name="$1"
  eval "var_value=\${$var_name-}"
  if [ -z "$var_value" ]; then
    echo "error: environment variable $var_name is required" >&2
    exit 1
  fi
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

require_env SERVER_NAME
require_env NATS_AUTH_TOKEN
require_env NATS_CLUSTER_AUTH_USER
require_env NATS_CLUSTER_AUTH_PASSWORD
require_env CLUSTER_ROUTES_SEED_PRIMARY
require_env CLUSTER_ROUTES_SEED_SECONDARY

cat > /tmp/nats-server.conf <<EOF
server_name: "$SERVER_NAME"

host: "$NATS_HOST"
port: $NATS_PORT

http_port: $NATS_HTTP_PORT

authorization {
  token: "$NATS_AUTH_TOKEN"
}

jetstream {
  store_dir: "$JETSTREAM_STORE_DIR"
}

cluster {
  name: "$CLUSTER_NAME"
  listen: "$NATS_CLUSTER_LISTEN"
  authorization {
    user: "$NATS_CLUSTER_AUTH_USER"
    password: "$NATS_CLUSTER_AUTH_PASSWORD"
  }
  routes = [
    "$CLUSTER_ROUTES_SEED_PRIMARY",
    "$CLUSTER_ROUTES_SEED_SECONDARY"
  ]
}
EOF

exec /nats-server --config /tmp/nats-server.conf
