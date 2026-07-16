#!/bin/bash

echo "==============================================="
echo "[Whisper Pro ASR] run.sh is executing!"
echo "==============================================="

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    echo "[Whisper Pro ASR] Reading configuration from HA addon options..."
    ASR_MODEL=$(jq -r '.ASR_MODEL // "Systran/faster-whisper-small"' "$OPTIONS_FILE")
    ASR_DEVICE=$(jq -r '.ASR_DEVICE // "CPU"' "$OPTIONS_FILE")
    ASR_COMPUTE_TYPE=$(jq -r '.ASR_COMPUTE_TYPE // "int8"' "$OPTIONS_FILE")
    ASR_BEAM_SIZE=$(jq -r '.ASR_BEAM_SIZE // "5"' "$OPTIONS_FILE")
    ASR_BATCH_SIZE=$(jq -r '.ASR_BATCH_SIZE // "1"' "$OPTIONS_FILE")
    ENABLE_VOCAL_SEPARATION=$(jq -r '.ENABLE_VOCAL_SEPARATION // "false"' "$OPTIONS_FILE")
    ENABLE_LD_PREPROCESSING=$(jq -r '.ENABLE_LD_PREPROCESSING // "true"' "$OPTIONS_FILE")
    DEBUG=$(jq -r '.DEBUG // "false"' "$OPTIONS_FILE")
else
    echo "[Whisper Pro ASR] No options.json found, using defaults..."
    ASR_MODEL="Systran/faster-whisper-small"
    ASR_DEVICE="CPU"
    ASR_COMPUTE_TYPE="int8"
    ASR_BEAM_SIZE="5"
    ASR_BATCH_SIZE="1"
    ENABLE_VOCAL_SEPARATION="false"
    ENABLE_LD_PREPROCESSING="true"
    DEBUG="false"
fi

export ASR_MODEL="${ASR_MODEL}"
export ASR_DEVICE="${ASR_DEVICE}"
export ASR_COMPUTE_TYPE="${ASR_COMPUTE_TYPE}"
export ASR_BEAM_SIZE="${ASR_BEAM_SIZE}"
export ASR_BATCH_SIZE="${ASR_BATCH_SIZE}"
export ENABLE_VOCAL_SEPARATION="${ENABLE_VOCAL_SEPARATION}"
export ENABLE_LD_PREPROCESSING="${ENABLE_LD_PREPROCESSING}"
export DEBUG="${DEBUG}"
export WHISPER_TEMP_DIR="/tmp/whisper"

# Persist model cache across restarts via HA's persistent /data folder
mkdir -p /data/model_cache
if [ ! -e /app/model_cache ]; then
    ln -s /data/model_cache /app/model_cache 2>/dev/null || true
fi

echo "[Whisper Pro ASR] Starting with:"
echo "  Model:                 $ASR_MODEL"
echo "  Device:                $ASR_DEVICE"
echo "  Compute type:          $ASR_COMPUTE_TYPE"
echo "  Beam size:             $ASR_BEAM_SIZE"
echo "  Batch size:            $ASR_BATCH_SIZE"
echo "  Vocal separation:      $ENABLE_VOCAL_SEPARATION"
echo "  LD preprocessing:      $ENABLE_LD_PREPROCESSING"
echo "  Debug:                 $DEBUG"

echo "[Whisper Pro ASR] Locating entry point..."
ENTRY=""
for candidate in /app/whisper_server.py /whisper_server.py /app/whisper_server/whisper_server.py; do
    if [ -f "$candidate" ]; then
        ENTRY="$candidate"
        break
    fi
done

if [ -z "$ENTRY" ]; then
    echo "[Whisper Pro ASR] whisper_server.py not found in common paths, searching filesystem..."
    ENTRY=$(find / -maxdepth 4 -name "whisper_server.py" 2>/dev/null | head -n 1)
fi

if [ -n "$ENTRY" ]; then
    echo "[Whisper Pro ASR] Found entry point: $ENTRY"
    cd "$(dirname "$ENTRY")"
    exec python3 "$ENTRY"
else
    echo "[Whisper Pro ASR] ERROR: could not locate whisper_server.py automatically."
    echo "[Whisper Pro ASR] Filesystem listing of / and /app for debugging:"
    ls -la /
    ls -la /app 2>/dev/null
    echo "[Whisper Pro ASR] Sleeping to keep container alive for inspection..."
    sleep infinity
fi
