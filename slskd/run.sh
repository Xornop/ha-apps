#!/bin/bash
set -e

CONFIG_PATH=/data/options.json
WG_CONF=/etc/wireguard/wg0.conf

opt() {
    jq -r "$1" "$CONFIG_PATH"
}

is_ipv4() {
    local ip="${1%%/*}"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    for o in "${BASH_REMATCH[@]:1}"; do
        [ "$o" -le 255 ] || return 1
    done
    return 0
}

SLSK_USERNAME=$(opt '.slsk_username')
SLSK_PASSWORD=$(opt '.slsk_password')
WEB_USERNAME=$(opt '.web_username')
WEB_PASSWORD=$(opt '.web_password')
LISTEN_PORT=$(opt '.listen_port')
DOWNLOADS_DIR=$(opt '.downloads_directory')
INCOMPLETE_DIR=$(opt '.incomplete_directory')
UPLOAD_SLOTS=$(opt '.upload_slots')
UPLOAD_SPEED_LIMIT=$(opt '.upload_speed_limit')
DOWNLOAD_SPEED_LIMIT=$(opt '.download_speed_limit')
REMOTE_CONFIGURATION=$(opt '.remote_configuration')
DIAGNOSTIC_LEVEL=$(opt '.diagnostic_level')
SHARED_DIRS=$(jq -r '.shared_directories | join(";")' "$CONFIG_PATH")

VPN_ENABLED=$(opt '.vpn_enabled')
WG_PRIVATE_KEY=$(opt '.wg_private_key')
WG_ADDRESS=$(opt '.wg_address')
WG_PEER_PUBLIC_KEY=$(opt '.wg_peer_public_key')
WG_PEER_ENDPOINT=$(opt '.wg_peer_endpoint')
WG_ALLOWED_IPS=$(opt '.wg_allowed_ips')

export SLSKD_SLSK_USERNAME="${SLSK_USERNAME}"
export SLSKD_SLSK_PASSWORD="${SLSK_PASSWORD}"
export SLSKD_USERNAME="${WEB_USERNAME}"
export SLSKD_PASSWORD="${WEB_PASSWORD}"
export SLSKD_SLSK_LISTEN_PORT="${LISTEN_PORT}"
export SLSKD_SHARED_DIR="${SHARED_DIRS}"
export SLSKD_UPLOAD_SLOTS="${UPLOAD_SLOTS}"
export SLSKD_REMOTE_CONFIGURATION="${REMOTE_CONFIGURATION}"
export SLSKD_DIAGNOSTIC_LEVEL="${DIAGNOSTIC_LEVEL}"
export SLSKD_HTTP_PORT="5030"
export SLSKD_NO_HTTPS="true"

if [ -n "${DOWNLOADS_DIR}" ] && [ "${DOWNLOADS_DIR}" != "null" ]; then
    export SLSKD_DOWNLOADS_DIR="${DOWNLOADS_DIR}"
fi
if [ -n "${INCOMPLETE_DIR}" ] && [ "${INCOMPLETE_DIR}" != "null" ]; then
    export SLSKD_INCOMPLETE_DIR="${INCOMPLETE_DIR}"
fi
if [ -n "${UPLOAD_SPEED_LIMIT}" ] && [ "${UPLOAD_SPEED_LIMIT}" != "0" ]; then
    export SLSKD_UPLOAD_SPEED_LIMIT="${UPLOAD_SPEED_LIMIT}"
fi
if [ -n "${DOWNLOAD_SPEED_LIMIT}" ] && [ "${DOWNLOAD_SPEED_LIMIT}" != "0" ]; then
    export SLSKD_DOWNLOAD_SPEED_LIMIT="${DOWNLOAD_SPEED_LIMIT}"
fi

echo "[slskd-addon] ensuring configured directories exist..."
while IFS= read -r dir; do
    [ -n "${dir}" ] && [ "${dir}" != "null" ] && mkdir -p "${dir}"
done <<< "$(jq -r '.shared_directories[]' "$CONFIG_PATH")"
[ -n "${DOWNLOADS_DIR}" ] && [ "${DOWNLOADS_DIR}" != "null" ] && mkdir -p "${DOWNLOADS_DIR}"
[ -n "${INCOMPLETE_DIR}" ] && [ "${INCOMPLETE_DIR}" != "null" ] && mkdir -p "${INCOMPLETE_DIR}"

# Split-tunnel approach: bring up WireGuard but DO NOT touch the default
# route. Only a local SOCKS5 proxy (danted), bound to egress via wg0, gets
# used - and only slskd's Soulseek connection is pointed at it (via
# slskd's native soulseek.connection.proxy setting). Everything else in
# the container (web UI, DNS, GitHub version check) keeps using the
# normal network untouched. This avoids needing a killswitch or any LAN
# route juggling: if wg0/danted ever goes down, slskd's proxy connection
# simply fails closed instead of falling back to a direct connection.
DANTED_PID=""

start_vpn() {
    mkdir -p "$(dirname "${WG_CONF}")"
    {
        echo "[Interface]"
        echo "PrivateKey = ${WG_PRIVATE_KEY}"
        echo ""
        echo "[Peer]"
        echo "PublicKey = ${WG_PEER_PUBLIC_KEY}"
        echo "Endpoint = ${WG_PEER_ENDPOINT}"
        echo "AllowedIPs = ${WG_ALLOWED_IPS}"
        echo "PersistentKeepalive = 25"
    } > "${WG_CONF}"
    chmod 600 "${WG_CONF}"

    echo "[slskd-addon] bringing up WireGuard tunnel..."

    if ! ip link add wg0 type wireguard; then
        echo "[slskd-addon] ERROR: failed to create the wg0 interface." >&2
        exit 1
    fi

    if ! wg setconf wg0 "${WG_CONF}"; then
        echo "[slskd-addon] ERROR: 'wg setconf' failed - check your WireGuard keys/endpoint." >&2
        ip link delete wg0 2>/dev/null || true
        exit 1
    fi

    ADDRESS_ASSIGNED=false
    IFS=',' read -ra WG_ADDRESSES <<< "${WG_ADDRESS}"
    for ADDR in "${WG_ADDRESSES[@]}"; do
        ADDR=$(echo "${ADDR}" | xargs)
        [ -z "${ADDR}" ] && continue
        is_ipv4 "${ADDR}" || { echo "[slskd-addon] skipping non-IPv4 address: ${ADDR}"; continue; }
        if ip address add "${ADDR}" dev wg0; then
            ADDRESS_ASSIGNED=true
        else
            echo "[slskd-addon] ERROR: failed to assign ${ADDR} to wg0." >&2
            ip link delete wg0 2>/dev/null || true
            exit 1
        fi
    done
    if [ "${ADDRESS_ASSIGNED}" != "true" ]; then
        echo "[slskd-addon] ERROR: wg_address has no usable IPv4 address." >&2
        ip link delete wg0 2>/dev/null || true
        exit 1
    fi

    ip link set mtu 1420 up dev wg0

    WG_OWN_IP="${WG_ADDRESSES[0]%%/*}"
    ip route add default dev wg0 table 200
    ip rule add from "${WG_OWN_IP}" table 200

    echo "[slskd-addon] waiting for handshake..."
    sleep 3
    wg show wg0

    echo "[slskd-addon] starting SOCKS5 proxy (danted), egress pinned to wg0..."
    cat > /etc/danted.conf << DANTED_EOF
logoutput: stderr
internal: 127.0.0.1 port = 1080
external: wg0
clientmethod: none
socksmethod: none
user.privileged: root
user.unprivileged: nobody
client pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
}
socks pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
}
DANTED_EOF

    danted -f /etc/danted.conf &
    DANTED_PID=$!
    sleep 1

    if ! kill -0 "${DANTED_PID}" 2>/dev/null; then
        echo "[slskd-addon] ERROR: danted failed to start." >&2
        exit 1
    fi

    export SLSKD_SOULSEEK_CONNECTION_PROXY_ENABLED="true"
    export SLSKD_SOULSEEK_CONNECTION_PROXY_ADDRESS="127.0.0.1"
    export SLSKD_SOULSEEK_CONNECTION_PROXY_PORT="1080"

    echo "[slskd-addon] SOCKS5 proxy up on 127.0.0.1:1080 via wg0 - slskd's Soulseek connection will use it. Web UI/DNS stay on the normal network."
}

stop_vpn() {
    if [ -n "${DANTED_PID}" ]; then
        kill "${DANTED_PID}" 2>/dev/null || true
    fi
    if ip link show wg0 > /dev/null 2>&1; then
        echo "[slskd-addon] tearing down WireGuard..."
        ip link delete wg0 || true
    fi
}

SLSKD_PID=""
cleanup() {
    echo "[slskd-addon] shutting down..."
    if [ -n "${SLSKD_PID}" ]; then
        kill "${SLSKD_PID}" 2>/dev/null || true
        wait "${SLSKD_PID}" 2>/dev/null || true
    fi
    stop_vpn
    exit 0
}
trap cleanup TERM INT

if [ "${VPN_ENABLED}" = "true" ]; then
    if [ -z "${WG_PRIVATE_KEY}" ] || [ "${WG_PRIVATE_KEY}" = "null" ] || \
       [ -z "${WG_PEER_PUBLIC_KEY}" ] || [ "${WG_PEER_PUBLIC_KEY}" = "null" ] || \
       [ -z "${WG_PEER_ENDPOINT}" ] || [ "${WG_PEER_ENDPOINT}" = "null" ]; then
        echo "[slskd-addon] ERROR: vpn_enabled is true but the WireGuard options aren't fully filled in." >&2
        exit 1
    fi
    start_vpn
fi

echo "[slskd-addon] shared directories: ${SLSKD_SHARED_DIR:-<none set>}"
echo "[slskd-addon] soulseek listen port: ${SLSKD_SLSK_LISTEN_PORT}"
echo "[slskd-addon] starting slskd..."

/app/slskd &
SLSKD_PID=$!
wait "${SLSKD_PID}"