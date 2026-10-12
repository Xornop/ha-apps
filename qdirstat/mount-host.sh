#!/bin/sh
OPTS=/data/options.json
DEV=$(grep -o '"mount_device": *"[^"]*"' "$OPTS" 2>/dev/null | sed 's/.*: *"\(.*\)"/\1/')

if [ -z "$DEV" ]; then
    echo "[qdirstat] geen mount_device ingesteld, host-schijf wordt niet gemount"
    exit 0
fi

echo "[qdirstat] uid: $(id -u), CapEff: $(grep CapEff /proc/self/status | awk '{print $2}')"
echo "[qdirstat] device: $(ls -lL "$DEV" 2>&1)"

mkdir -p /scan/host

if OUT=$(mount -o ro "$DEV" /scan/host 2>&1); then
    echo "[qdirstat] $DEV gemount op /scan/host (read-only)"
elif OUT=$(mount "$DEV" /scan/host 2>&1); then
    echo "[qdirstat] $DEV gemount op /scan/host (read-write, ro was niet mogelijk)"
else
    echo "[qdirstat] mounten van $DEV mislukt: $OUT"
fi

exit 0
