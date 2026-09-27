#!/bin/sh
# Reads /data/options.json (the app's user config), exports it as the
# environment variables DroppedNeedle expects, then symlinks its hardcoded
# /app/* and /data paths onto the app's persistent HA volumes before handing
# off to the original image entrypoint (preserved as /entrypoint.upstream.sh
# so the image's original CMD keeps working unmodified).
set -e

OPTIONS_FILE=/data/options.json

opt() {
    python3 -c "
import json
with open('$OPTIONS_FILE') as f:
    d = json.load(f)
v = d.get('$1', '')
print(v if v is not None else '')
"
}

export PUID="$(opt puid)"
export PGID="$(opt pgid)"
export UMASK="$(opt umask)"
export PORT="8688"
export BIND_HOST="$(opt bind_host)"
export TRUSTED_PROXY_IPS="$(opt trusted_proxy_ips)"
export TZ="$(opt tz)"
export SLSKD_DOWNLOADS_PATH="$(opt slskd_downloads_path)"

# /config is the app_config map (persistent, unique to this app).
# /media is the media map (shared library + download-client completions).
mkdir -p /config/cache /config/plugins /config/imports /media

for p in config cache plugins imports; do
    [ -L "/app/$p" ] || rm -rf "/app/$p"
done

ln -sfn /config /app/config
ln -sfn /config/cache /app/cache
ln -sfn /config/plugins /app/plugins
ln -sfn /config/imports /app/imports
ln -sfn /media /data

exec /entrypoint.upstream.sh "$@"