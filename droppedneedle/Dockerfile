FROM droppedneedle/droppedneedle:latest

# Preserve the original entrypoint script under a new name, and replace
# /entrypoint.sh with our own, which does app-specific setup and then hands
# off to it.
RUN mv /entrypoint.sh /entrypoint.upstream.sh
COPY docker-entrypoint-wrapper.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

# Declared explicitly (not just inherited from FROM) so the local Supervisor
# build reliably keeps them: matches the upstream image's own
# ["tini","--","/entrypoint.sh"] / ["python","-m","maintenance.automatic_upgrade","--start-target"].
ENTRYPOINT [ "tini", "--", "/entrypoint.sh" ]
CMD [ "python", "-m", "maintenance.automatic_upgrade", "--start-target" ]

LABEL \
    io.hass.version="1.0.0" \
    io.hass.type="app" \
    io.hass.arch="amd64|aarch64"