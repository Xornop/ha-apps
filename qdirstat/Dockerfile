ARG BUILD_FROM=jlesage/qdirstat:latest
FROM ${BUILD_FROM}

ENV WEB_LISTENING_PORT=5800 \
    SECURE_CONNECTION=0 \
    WEB_AUTHENTICATION=0 \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    USER_ID=0 \
    GROUP_ID=0

COPY mount-host.sh /etc/cont-init.d/60-mount-host.sh
COPY log-ts.sh /usr/local/bin/log-ts.sh
RUN chmod 755 /etc/cont-init.d/60-mount-host.sh /usr/local/bin/log-ts.sh

ENTRYPOINT ["/usr/local/bin/log-ts.sh"]
CMD []

LABEL io.hass.name="QDirStat" \
      io.hass.description="QDirStat disk usage analyzer" \
      io.hass.type="addon"
