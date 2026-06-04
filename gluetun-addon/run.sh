#!/usr/bin/with-contenv bashio

if bashio::config.has_value 'tz'; then
    export TZ="$(bashio::config 'tz')"
fi

if bashio::config.has_value 'server_countries'; then
    export SERVER_COUNTRIES="$(bashio::config 'server_countries')"
fi

export VPN_SERVICE_PROVIDER="$(bashio::config 'vpn_provider')"
export VPN_TYPE="$(bashio::config 'vpn_type')"

if bashio::config.has_value 'openvpn_user'; then
    export OPENVPN_USER="$(bashio::config 'openvpn_user')"
    export OPENVPN_PASSWORD="$(bashio::config 'openvpn_password')"
fi

if bashio::config.has_value 'wireguard_private_key'; then
    export WIREGUARD_PRIVATE_KEY="$(bashio::config 'wireguard_private_key')"
    export WIREGUARD_ADDRESSES="$(bashio::config 'wireguard_addresses')"
fi

# Gluetun verwacht SHADOWSOCKS, niet SHADOWSOCKS_ENABLED
if bashio::config.true 'shadowsocks_enabled'; then
    export SHADOWSOCKS="on"
    export SHADOWSOCKS_PORT="$(bashio::config 'shadowsocks_port' '8388')"
    export SHADOWSOCKS_PASSWORD="$(bashio::config 'shadowsocks_password' 'gluetun')"
    export SHADOWSOCKS_METHOD="$(bashio::config 'shadowsocks_method' 'aes-256-gcm')"
else
    export SHADOWSOCKS="off"
fi

# Gluetun verwacht HTTPPROXY, niet HTTPPROXY_ENABLED
if bashio::config.true 'http_proxy_enabled'; then
    export HTTPPROXY="on"
    export HTTPPROXY_PORT="$(bashio::config 'http_proxy_port' '8888')"
else
    export HTTPPROXY="off"
fi

export DOT="off"
export UPDATER_PERIOD="24h"
export LOG_LEVEL="info"
export LOG_FORMATTER="text"
export PPROF_ENABLED="no"
export PPROF_BLOCK_PROFILE_RATE="0"
export PPROF_MUTEX_PROFILE_RATE="0"
export FIREWALL_ENABLED_DISABLING_IT_SHOOTS_YOU_IN_YOUR_FOOT="on"

bashio::log.info "Starting Gluetun VPN..."
exec /usr/local/bin/gluetun
