#!/bin/bash
set -e

CONFIG_PATH=/data/options.json
WG_CONF=/etc/wireguard/wg0.conf

opt() {
    jq -r "$1" "$CONFIG_PATH"
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
WG_DNS=$(opt '.wg_dns')
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

# Web UI is only reachable on the fixed port below (no Ingress - see README),
# so pin it and skip HTTPS, which Ingress/your own reverse proxy can handle.
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

# Make sure every configured folder actually exists - slskd shouldn't have
# to be the one to create shared/download/incomplete directories.
echo "[slskd-addon] ensuring configured directories exist..."
while IFS= read -r dir; do
    if [ -n "${dir}" ] && [ "${dir}" != "null" ]; then
        mkdir -p "${dir}"
    fi
done <<< "$(jq -r '.shared_directories[]' "$CONFIG_PATH")"

if [ -n "${DOWNLOADS_DIR}" ] && [ "${DOWNLOADS_DIR}" != "null" ]; then
    mkdir -p "${DOWNLOADS_DIR}"
fi

if [ -n "${INCOMPLETE_DIR}" ] && [ "${INCOMPLETE_DIR}" != "null" ]; then
    mkdir -p "${INCOMPLETE_DIR}"
fi

start_vpn() {
    if [ -z "${WG_PRIVATE_KEY}" ] || [ "${WG_PRIVATE_KEY}" = "null" ]; then
        echo "[slskd-addon] vpn_enabled is true but wg_private_key is empty - skipping VPN, starting slskd directly."
        return 1
    fi

    {
        echo "[Interface]"
        echo "PrivateKey = ${WG_PRIVATE_KEY}"
        echo "Address = ${WG_ADDRESS}"
        if [ -n "${WG_DNS}" ] && [ "${WG_DNS}" != "null" ]; then
            echo "DNS = ${WG_DNS}"
        fi
        echo ""
        echo "[Peer]"
        echo "PublicKey = ${WG_PEER_PUBLIC_KEY}"
        echo "Endpoint = ${WG_PEER_ENDPOINT}"
        echo "AllowedIPs = ${WG_ALLOWED_IPS}"
        echo "PersistentKeepalive = 25"
    } > "${WG_CONF}"
    chmod 600 "${WG_CONF}"

    echo "[slskd-addon] bringing up WireGuard tunnel (full-tunnel, no port forwarding)..."
    wg-quick up wg0

    # Kill switch: once the tunnel is up, only allow outbound traffic over
    # loopback, the tunnel itself, and the encrypted handshake to the VPN
    # endpoint (which necessarily leaves via the host interface, not wg0).
    WG_ENDPOINT_HOST="${WG_PEER_ENDPOINT%%:*}"
    WG_ENDPOINT_PORT="${WG_PEER_ENDPOINT##*:}"
    WG_ENDPOINT_IP=$(getent hosts "${WG_ENDPOINT_HOST}" | awk '{print $1}' | head -n1)
    WG_ENDPOINT_IP="${WG_ENDPOINT_IP:-${WG_ENDPOINT_HOST}}"

    iptables -F OUTPUT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A OUTPUT -o wg0 -j ACCEPT
    iptables -A OUTPUT -d "${WG_ENDPOINT_IP}" -p udp --dport "${WG_ENDPOINT_PORT}" -j ACCEPT
    iptables -P OUTPUT DROP

    echo "[slskd-addon] WireGuard is up and the kill switch is active - traffic can only leave via the tunnel."
}

stop_vpn() {
    if ip link show wg0 > /dev/null 2>&1; then
        echo "[slskd-addon] tearing down WireGuard..."
        wg-quick down wg0 || true
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
    start_vpn || true
fi

echo "[slskd-addon] shared directories: ${SLSKD_SHARED_DIR:-<none set>}"
echo "[slskd-addon] soulseek listen port: ${SLSKD_SLSK_LISTEN_PORT}"
echo "[slskd-addon] starting slskd..."

/app/slskd &
SLSKD_PID=$!
wait "${SLSKD_PID}"
