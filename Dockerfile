FROM nats:2.11.14

ENV NATS_HOST=0.0.0.0 \
    NATS_PORT=4222 \
    NATS_HTTP_PORT=8222 \
    NATS_CLUSTER_LISTEN=0.0.0.0:6222 \
    CLUSTER_NAME=cluster \
    JETSTREAM_STORE_DIR=/data/jetstream

COPY nats-server.conf /etc/nats/nats-server.conf

EXPOSE 4222 6222 8222

ENTRYPOINT ["/nats-server"]
CMD ["--config", "/etc/nats/nats-server.conf"]
