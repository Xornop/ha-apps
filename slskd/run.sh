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

PORT_FORWARD_METHOD=$(opt '.port_forward_method')
NATPMP_GATEWAY_OVERRIDE=$(opt '.wg_natpmp_gateway')

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
NATPMP_RENEW_PID=""
WG_OWN_IP=""
WG_GATEWAY=""

# --- Port forwarding backend abstraction -----------------------------------
# Provider-agnostic by design. Each supported method gets its own
# try_portforward_<method>() function that echoes the forwarded port on
# stdout and returns non-zero on failure. To add a provider-specific
# method later (e.g. a PIA/AirVPN API), write a new function following
# this contract and add a case for it in request_port_forward().

# NAT-PMP - not tied to any single provider, works with any gateway that
# answers NAT-PMP requests (this is how ProtonVPN's WireGuard gateways
# happen to support it, but the protocol itself is generic).
try_portforward_natpmp() {
    local gw="$1"
    local out port
    out=$(timeout 20 natpmpc -a 1 0 tcp 60 -g "${gw}" 2>&1) || true
    echo "${out}" | sed 's/^/[slskd-addon][natpmp] /' >&2
    port=$(echo "${out}" | grep -oP 'Mapped public port \K[0-9]+' | head -n1)
    [ -n "${port}" ] || return 1
    echo "${port}"
}

# Renewal now mirrors the initial request: it's timeout-guarded (so a
# hung natpmpc can't silently wedge the renewal loop) and its output is
# always logged, so a failure shows *why* instead of just "failed".
renew_portforward_natpmp() {
    local gw="$1" port="$2"
    local out
    if out=$(timeout 20 natpmpc -a 1 "${port}" tcp 60 -g "${gw}" 2>&1); then
        echo "${out}" | sed 's/^/[slskd-addon][natpmp-renew] /' >&2
        return 0
    else
        echo "${out}" | sed 's/^/[slskd-addon][natpmp-renew] /' >&2
        return 1
    fi
}

request_port_forward() {
    local gw="$1"
    case "${PORT_FORWARD_METHOD}" in
        natpmp)
            try_portforward_natpmp "${gw}"
            ;;
        none|""|null)
            return 1
            ;;
        *)
            echo "[slskd-addon][portfwd] WARNING: unknown port_forward_method '${PORT_FORWARD_METHOD}', skipping port forwarding." >&2
            return 1
            ;;
    esac
}
# -----------------------------------------------------------------------------

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
            WG_OWN_IP="${ADDR%%/*}"
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

    # Inbound port forwarding is optional and provider-agnostic. It never
    # blocks startup or fails the VPN: if it doesn't work, we just log a
    # warning and keep the static listen_port. Outbound traffic (and the
    # "no leaks" guarantee) is unaffected either way.
    if [ "${PORT_FORWARD_METHOD}" = "none" ] || [ -z "${PORT_FORWARD_METHOD}" ] || [ "${PORT_FORWARD_METHOD}" = "null" ]; then
        echo "[slskd-addon][portfwd] disabled (port_forward_method=none) - using static listen_port ${SLSKD_SLSK_LISTEN_PORT}."
    else
        if [ -n "${NATPMP_GATEWAY_OVERRIDE}" ] && [ "${NATPMP_GATEWAY_OVERRIDE}" != "null" ] && is_ipv4 "${NATPMP_GATEWAY_OVERRIDE}"; then
            WG_GATEWAY="${NATPMP_GATEWAY_OVERRIDE}"
            echo "[slskd-addon][portfwd] using configured gateway override: ${WG_GATEWAY}"
        else
            WG_GATEWAY="${WG_OWN_IP%.*}.1"
            echo "[slskd-addon][portfwd] no wg_natpmp_gateway set, assuming provider default gateway: ${WG_GATEWAY} (set wg_natpmp_gateway if your provider uses a different one)"
        fi
        ip route add "${WG_GATEWAY}/32" dev wg0 2>/dev/null || true

        echo "[slskd-addon][portfwd] requesting inbound port forward via ${PORT_FORWARD_METHOD} (gateway ${WG_GATEWAY})..."
        FORWARDED_PORT=$(request_port_forward "${WG_GATEWAY}") || FORWARDED_PORT=""

        if [ -n "${FORWARDED_PORT}" ]; then
            echo "[slskd-addon][portfwd] SUCCESS - forwarded port ${FORWARDED_PORT}/tcp, incoming connections (uploads) now go through the VPN too."
            export SLSKD_SLSK_LISTEN_PORT="${FORWARDED_PORT}"
            if [ "${PORT_FORWARD_METHOD}" = "natpmp" ]; then
                (
                    FAIL_STREAK=0
                    while true; do
                        sleep 45
                        if renew_portforward_natpmp "${WG_GATEWAY}" "${FORWARDED_PORT}" > /dev/null; then
                            FAIL_STREAK=0
                        else
                            FAIL_STREAK=$((FAIL_STREAK + 1))
                            echo "[slskd-addon][portfwd] WARNING: NAT-PMP renewal failed (attempt ${FAIL_STREAK}) - forwarded port may drop. See [natpmp-renew] lines above for the reason." >&2
                            # After 3 consecutive failures (~2-3 min), the mapping
                            # has almost certainly expired server-side. Stop
                            # trying to "renew" a dead mapping and request a
                            # fresh one instead - covers cases like a brief wg0
                            # handshake drop or the gateway rotating mappings.
                            if [ "${FAIL_STREAK}" -ge 3 ]; then
                                echo "[slskd-addon][portfwd] re-requesting a fresh NAT-PMP mapping after ${FAIL_STREAK} failed renewals..." >&2
                                NEW_PORT=$(try_portforward_natpmp "${WG_GATEWAY}") || NEW_PORT=""
                                if [ -n "${NEW_PORT}" ]; then
                                    echo "[slskd-addon][portfwd] re-acquired mapping: port ${NEW_PORT}/tcp. Note: slskd's listen port is not updated at runtime - restart the add-on to pick up ${NEW_PORT} if it differs from ${FORWARDED_PORT}." >&2
                                    FORWARDED_PORT="${NEW_PORT}"
                                    FAIL_STREAK=0
                                else
                                    echo "[slskd-addon][portfwd] re-acquisition also failed - will keep retrying every 45s." >&2
                                fi
                            fi
                        fi
                    done
                ) &
                NATPMP_RENEW_PID=$!
            fi
        else
            echo "[slskd-addon][portfwd] WARNING: no forwarded port obtained via ${PORT_FORWARD_METHOD} (provider may not support it, or wg_natpmp_gateway is wrong). Outbound Soulseek traffic still goes through the VPN and nothing leaks, but incoming connections (uploads) likely won't work." >&2
        fi
    fi
}

stop_vpn() {
    if [ -n "${NATPMP_RENEW_PID}" ]; then
        kill "${NATPMP_RENEW_PID}" 2>/dev/null || true
    fi
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

# The APP_DIR env var alone hasn't been reliably picked up by slskd in
# testing, so pass it explicitly via --app-dir too (command-line args take
# the highest precedence per slskd's own config source hierarchy, so this
# is guaranteed to win regardless of why the env var isn't landing).
/app/slskd --app-dir "${APP_DIR:-/config}" &
SLSKD_PID=$!
wait "${SLSKD_PID}"