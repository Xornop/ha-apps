ARG BUILD_FROM
FROM ghcr.io/qdm12/gluetun:v3.39.0 AS gluetun
FROM $BUILD_FROM

RUN apk add --no-cache \
    ca-certificates \
    iptables \
    iptables-legacy \
    wireguard-tools \
    tzdata

COPY --from=gluetun /gluetun-entrypoint /usr/local/bin/gluetun
COPY --from=gluetun /etc/ssl/certs /etc/ssl/certs

RUN mkdir -p /gluetun

COPY run.sh /addon/run.sh
COPY s6-services/ /etc/services.d/
RUN chmod a+x /addon/run.sh /etc/services.d/*/run

EXPOSE 8388 8000

ENV STORAGE_FILEPATH=/gluetun/servers.json

ENTRYPOINT ["/init"]
