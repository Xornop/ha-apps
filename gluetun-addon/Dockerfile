ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    ca-certificates \
    iptables \
    iptables-legacy \
    wireguard-tools \
    tzdata \
    openvpn

COPY --from=ghcr.io/qdm12/gluetun:v3.39.0 /gluetun-entrypoint /usr/local/bin/gluetun
COPY --from=ghcr.io/qdm12/gluetun:v3.39.0 /etc/ssl /etc/ssl
COPY --from=ghcr.io/qdm12/gluetun:v3.39.0 /usr/sbin/openvpn2.5 /usr/sbin/openvpn2.5
COPY --from=ghcr.io/qdm12/gluetun:v3.39.0 /usr/sbin/openvpn2.6 /usr/sbin/openvpn2.6
COPY --from=ghcr.io/qdm12/gluetun:v3.39.0 /usr/lib/unbound /usr/lib/unbound
COPY --from=ghcr.io/qdm12/gluetun:v3.39.0 /usr/sbin/unbound /usr/sbin/unbound

RUN mkdir -p /gluetun /tmp/gluetun

COPY run.sh /addon/run.sh
COPY s6-services/ /etc/services.d/
RUN chmod a+x /addon/run.sh /etc/services.d/*/run

EXPOSE 8388 8000

ENV STORAGE_FILEPATH=/gluetun/servers.json

ENTRYPOINT ["/init"]
