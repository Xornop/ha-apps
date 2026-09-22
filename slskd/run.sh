#!/bin/bash
set -e

CONFIG_PATH=/data/options.json

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

echo "[slskd-addon] shared directories: ${SLSKD_SHARED_DIR:-<none set>}"
echo "[slskd-addon] soulseek listen port: ${SLSKD_SLSK_LISTEN_PORT}"
echo "[slskd-addon] starting slskd..."

exec /app/slskd
