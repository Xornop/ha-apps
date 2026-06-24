#!/usr/bin/with-contenv bashio

# Read options from HA config
MEDIA_SERVER_TYPE=$(bashio::config 'media_server_type')
MEDIA_SERVER_URL=$(bashio::config 'media_server_url')
MEDIA_SERVER_API_KEY=$(bashio::config 'media_server_api_key')
SONARR_URL=$(bashio::config 'sonarr_url')
SONARR_API_KEY=$(bashio::config 'sonarr_api_key')
INTERVAL=$(bashio::config 'interval')
PREFETCH_NUM=$(bashio::config 'prefetch_num')
REQUEST_SEASONS=$(bashio::config 'request_seasons')
LOG_LEVEL=$(bashio::config 'log_level')
USERS=$(bashio::config 'users')
LIBRARIES=$(bashio::config 'libraries')

# Build TOML config
CONFIG="
interval = ${INTERVAL}
log_level = \"${LOG_LEVEL}\"
prefetch_num = ${PREFETCH_NUM}
request_seasons = ${REQUEST_SEASONS}

[media_server]
type = \"${MEDIA_SERVER_TYPE}\"
url = \"${MEDIA_SERVER_URL}\"
api_key = \"${MEDIA_SERVER_API_KEY}\"

[sonarr]
url = \"${SONARR_URL}\"
api_key = \"${SONARR_API_KEY}\"
"

if bashio::config.has_value 'users'; then
    CONFIG="${CONFIG}
users = [$(echo "$USERS" | sed 's/,/","/g' | sed 's/^/\"/' | sed 's/$/\"/')]"
fi

if bashio::config.has_value 'libraries'; then
    CONFIG="${CONFIG}
libraries = [$(echo "$LIBRARIES" | sed 's/,/","/g' | sed 's/^/\"/' | sed 's/$/\"/')]"
fi

bashio::log.info "Starting Prefetcharr..."
bashio::log.info "Media server: ${MEDIA_SERVER_TYPE} @ ${MEDIA_SERVER_URL}"
bashio::log.info "Sonarr: ${SONARR_URL}"

export PREFETCHARR_CONFIG="${CONFIG}"

exec /usr/local/bin/prefetcharr
