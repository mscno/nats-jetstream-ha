FROM nats:2.12.5-alpine

ENV NATS_HOST=0.0.0.0 \
    NATS_PORT=4222 \
    NATS_HTTP_PORT=8222 \
    NATS_CLUSTER_LISTEN=0.0.0.0:6222 \
    CLUSTER_NAME=cluster \
    JETSTREAM_STORE_DIR=/data/jetstream

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 4222 6222 8222

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
