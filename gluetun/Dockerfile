ARG BUILD_FROM=ghcr.io/home-assistant/base:latest
FROM ${BUILD_FROM}

RUN apk add --no-cache --update \
    go \
    git \
    ca-certificates \
    iptables \
    iptables-legacy \
    tzdata \
    wireguard-tools \
    unbound

# Install OpenVPN 2.5 en 2.6
RUN apk add --no-cache --update -X "https://dl-cdn.alpinelinux.org/alpine/v3.17/main" openvpn~2.5 && \
    mv /usr/sbin/openvpn /usr/sbin/openvpn2.5 && \
    apk del openvpn && \
    apk add --no-cache --update openvpn && \
    mv /usr/sbin/openvpn /usr/sbin/openvpn2.6 && \
    rm -rf /var/cache/apk/*

# Build Gluetun from source
ARG GLUETUN_VERSION=v3.39.0
RUN git clone --depth 1 --branch ${GLUETUN_VERSION} https://github.com/qdm12/gluetun.git /tmp/gluetun && \
    cd /tmp/gluetun && \
    go build -o /usr/local/bin/gluetun ./cmd/gluetun && \
    chmod 755 /usr/local/bin/gluetun && \
    rm -rf /tmp/gluetun

RUN mkdir -p /gluetun

COPY run.sh /etc/services.d/gluetun/run
RUN chmod a+x /etc/services.d/gluetun/run

EXPOSE 8388 8888 8000

ENV STORAGE_FILEPATH=/gluetun/servers.json

ENTRYPOINT ["/init"]
