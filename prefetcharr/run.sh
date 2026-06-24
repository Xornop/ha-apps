#!/usr/bin/with-contenv bashio

MEDIA_SERVER_TYPE=$(bashio::config 'media_server_type')
MEDIA_SERVER_URL=$(bashio::config 'media_server_url')
MEDIA_SERVER_API_KEY=$(bashio::config 'media_server_api_key')
SONARR_URL=$(bashio::config 'sonarr_url')
SONARR_API_KEY=$(bashio::config 'sonarr_api_key')
INTERVAL=$(bashio::config 'interval')
PREFETCH_NUM=$(bashio::config 'prefetch_num')
REQUEST_SEASONS=$(bashio::config 'request_seasons')
LOG_LEVEL=$(bashio::config 'log_level')

CONFIG_FILE=/tmp/prefetcharr.toml

cat > "${CONFIG_FILE}" << TOML
interval = ${INTERVAL}
log_level = "${LOG_LEVEL}"
prefetch_num = ${PREFETCH_NUM}
request_seasons = ${REQUEST_SEASONS}

[media_server]
type = "${MEDIA_SERVER_TYPE}"
url = "${MEDIA_SERVER_URL}"
api_key = "${MEDIA_SERVER_API_KEY}"

[sonarr]
url = "${SONARR_URL}"
api_key = "${SONARR_API_KEY}"
TOML

if bashio::config.has_value 'users'; then
    USERS=$(bashio::config 'users')
    echo "users = [$(echo "$USERS" | sed 's/,/\", \"/g' | sed 's/^/\"/' | sed 's/$/\"/')]" >> "${CONFIG_FILE}"
fi

if bashio::config.has_value 'libraries'; then
    LIBRARIES=$(bashio::config 'libraries')
    echo "libraries = [$(echo "$LIBRARIES" | sed 's/,/\", \"/g' | sed 's/^/\"/' | sed 's/$/\"/')]" >> "${CONFIG_FILE}"
fi

bashio::log.info "Starting Prefetcharr..."
bashio::log.info "Media server: ${MEDIA_SERVER_TYPE} @ ${MEDIA_SERVER_URL}"
bashio::log.info "Sonarr: ${SONARR_URL}"

exec /usr/local/bin/prefetcharr --config "${CONFIG_FILE}"
