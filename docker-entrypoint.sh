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

cat > /tmp/nats-server.conf <<EOF
server_name: "$SERVER_NAME_ESCAPED"

host: "$NATS_HOST_ESCAPED"
port: $NATS_PORT

http_port: $NATS_HTTP_PORT

authorization {
  token: "$NATS_AUTH_TOKEN_ESCAPED"
}

jetstream {
  store_dir: "$JETSTREAM_STORE_DIR_ESCAPED"
}

cluster {
  name: "$CLUSTER_NAME_ESCAPED"
  listen: "$NATS_CLUSTER_LISTEN_ESCAPED"
  authorization {
    user: "$NATS_CLUSTER_AUTH_USER_ESCAPED"
    password: "$NATS_CLUSTER_AUTH_PASSWORD_ESCAPED"
  }
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
