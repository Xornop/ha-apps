FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache python3

COPY responder.py /responder.py
COPY run.sh /run.sh

RUN chmod a+x /run.sh

LABEL io.hass.name="HA mDNS Aliases"
LABEL io.hass.description="Publishes additional .local hostnames for Home Assistant"
LABEL io.hass.type="app"
LABEL io.hass.version="1.2.0"
LABEL io.hass.arch="amd64|aarch64|armv7|armhf|i386"

CMD ["/run.sh"]
