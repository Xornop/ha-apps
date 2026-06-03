ARG BUILD_FROM
FROM $BUILD_FROM

# Runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    iptables \
    iptables-legacy \
    wireguard-tools \
    tzdata \
    python3 \
    py3-pip \
    py3-flask \
    py3-requests

RUN pip3 install --break-system-packages flask-cors

# Copy gluetun binary from official image
COPY --from=ghcr.io/qdm12/gluetun:v3.40.0 /gluetun /usr/local/bin/gluetun

# Create gluetun data directory
RUN mkdir -p /gluetun

# Copy addon files
COPY run.sh /addon/run.sh
COPY startup.sh /addon/startup.sh
COPY gluetun-config.sh /addon/gluetun-config.sh
COPY web/ /web/
COPY s6-services/ /etc/services.d/
RUN chmod a+x /addon/*.sh /etc/services.d/*/run

EXPOSE 8888 8388 8000

ENV VPN_SERVICE_PROVIDER=pia \
    VPN_TYPE=openvpn \
    FIREWALL_ENABLED_DISABLING_IT_SHOOTS_YOU_IN_YOUR_FOOT=on \
    HTTP_CONTROL_SERVER_ADDRESS=":8000" \
    STORAGE_FILEPATH=/gluetun/servers.json

ENTRYPOINT ["/init"]
