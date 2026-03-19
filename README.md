# `mscno/nats-jetstream-ha`

Container image for running a three-node NATS cluster with JetStream enabled on Railway.

Published image:

```text
ghcr.io/mscno/nats-jetstream-ha:latest
```

The image wraps the official NATS image and starts `nats-server` with the bundled config at `/etc/nats/nats-server.conf`.

## What The Container Expects

The image exposes:

- `4222` for NATS client traffic
- `6222` for cluster routes
- `8222` for the monitoring HTTP API

Environment variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `SERVER_NAME` | yes | none | Unique NATS server name per node |
| `NATS_HOST` | no | `0.0.0.0` | Client listener bind address |
| `NATS_PORT` | no | `4222` | Client listener port |
| `NATS_HTTP_PORT` | no | `8222` | Monitoring HTTP port |
| `NATS_CLUSTER_LISTEN` | no | `0.0.0.0:6222` | Cluster route listener address |
| `JETSTREAM_STORE_DIR` | no | `/data/jetstream` | JetStream file storage directory |
| `CLUSTER_NAME` | no | `cluster` | Shared NATS cluster name |
| `CLUSTER_ROUTES_SEED` | yes | none | Comma-separated route URLs for the other nodes |

Important:

- Mount the volume at `/data`.
- Keep `JETSTREAM_STORE_DIR` under that mount, for example `/data/jetstream`.
- Do not share a single volume between nodes.
- `CLUSTER_ROUTES_SEED` must contain valid route URLs only, such as `nats://host:6222`.
- Do not use malformed routes like `nats://nats-2:some-host:6222`. That form is invalid and can crash route startup.
- These env vars intentionally cover the common deployment knobs only. Advanced NATS features should still go in a custom config if you need them.

## Railway Topology

For Railway HA, use three separate services:

- `nats-1`
- `nats-2`
- `nats-3`

Each service should use:

- image: `ghcr.io/mscno/nats-jetstream-ha:latest`
- one attached volume
- volume mount path: `/data`
- no Railway replicas

This matters because Railway volumes are attached per service. A three-node JetStream cluster on Railway should be three services with one volume each, not one service with three replicas.

## Per-Service Variables

Set these environment variables on each Railway service.

### `nats-1`

```text
SERVER_NAME=nats-1
NATS_HOST=0.0.0.0
NATS_PORT=4222
NATS_HTTP_PORT=8222
NATS_CLUSTER_LISTEN=0.0.0.0:6222
CLUSTER_NAME=natscluster
JETSTREAM_STORE_DIR=/data/jetstream
CLUSTER_ROUTES_SEED=nats://${{nats-2.RAILWAY_PRIVATE_DOMAIN}}:6222,nats://${{nats-3.RAILWAY_PRIVATE_DOMAIN}}:6222
```

### `nats-2`

```text
SERVER_NAME=nats-2
NATS_HOST=0.0.0.0
NATS_PORT=4222
NATS_HTTP_PORT=8222
NATS_CLUSTER_LISTEN=0.0.0.0:6222
CLUSTER_NAME=natscluster
JETSTREAM_STORE_DIR=/data/jetstream
CLUSTER_ROUTES_SEED=nats://${{nats-1.RAILWAY_PRIVATE_DOMAIN}}:6222,nats://${{nats-3.RAILWAY_PRIVATE_DOMAIN}}:6222
```

### `nats-3`

```text
SERVER_NAME=nats-3
NATS_HOST=0.0.0.0
NATS_PORT=4222
NATS_HTTP_PORT=8222
NATS_CLUSTER_LISTEN=0.0.0.0:6222
CLUSTER_NAME=natscluster
JETSTREAM_STORE_DIR=/data/jetstream
CLUSTER_ROUTES_SEED=nats://${{nats-1.RAILWAY_PRIVATE_DOMAIN}}:6222,nats://${{nats-2.RAILWAY_PRIVATE_DOMAIN}}:6222
```

Route syntax is the critical detail. Use:

```text
nats://${{nats-2.RAILWAY_PRIVATE_DOMAIN}}:6222
```

Not:

```text
nats://nats-2:${{nats-2.RAILWAY_PRIVATE_DOMAIN}}:6222
```

## Railway Service Config

`railway.toml` cannot define all three services in one file. Create three Railway services and point each one at the same image or repo.

If you want config-as-code per service, the service file can stay minimal:

```toml
[build]
image = "ghcr.io/mscno/nats-jetstream-ha:latest"

[deploy]
restartPolicyType = "ALWAYS"
restartPolicyMaxRetries = 10
```

The container already starts with the bundled config, so you do not need a custom start command unless you want to override it.

## Monitoring And Health

Port `8222` is the HTTP monitoring port. It is useful for:

- `/healthz` for health checks
- `/routez` to confirm cluster routes
- `/jsz` to inspect JetStream state
- `/varz` and `/connz` for server and connection stats

Recommended exposure:

- expose `4222` publicly only if clients need it
- keep `6222` private
- keep `8222` private unless you explicitly need remote monitoring

## Operational Notes

- JetStream HA depends on stream and consumer replication, not only on running three servers.
- Create streams with `num_replicas: 3` if you want three-node durability.
- Deploy one node at a time. Restarting all three services together can drop quorum and cause downtime.
- Clean restarts with the same persistent volumes should normally cause downtime, not data loss.
- Abrupt failure of all nodes at once can still lose recent acknowledged messages because disk sync is not the same as quorum acknowledgement.

Example stream config:

```json
{
  "name": "EVENTS",
  "subjects": ["events.>"],
  "storage": "file",
  "num_replicas": 3
}
```

## Local Docker Example

This image can also be run outside Railway:

```bash
docker run -d \
  --name nats-1 \
  -p 4222:4222 \
  -p 6222:6222 \
  -p 8222:8222 \
  -v nats_data:/data \
  -e SERVER_NAME=nats-1 \
  -e NATS_HOST=0.0.0.0 \
  -e NATS_PORT=4222 \
  -e NATS_HTTP_PORT=8222 \
  -e NATS_CLUSTER_LISTEN=0.0.0.0:6222 \
  -e CLUSTER_NAME=natscluster \
  -e JETSTREAM_STORE_DIR=/data/jetstream \
  -e CLUSTER_ROUTES_SEED='nats://nats-2:6222,nats://nats-3:6222' \
  ghcr.io/mscno/nats-jetstream-ha:latest
```

For a real cluster, run three nodes on the same Docker network and give each node routes to the other two nodes.

If you need auth, accounts, TLS, JetStream sizing limits, or other non-trivial NATS options, use this image as a base and replace the bundled config with your own.
