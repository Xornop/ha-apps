#!/bin/bash

echo "==============================================="
echo "[Whisper ASR] run.sh is executing!"
echo "==============================================="

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    echo "[Whisper ASR] Reading configuration from HA addon options..."
    ASR_MODEL=$(jq -r '.ASR_MODEL // "small"' "$OPTIONS_FILE")
    ASR_ENGINE=$(jq -r '.ASR_ENGINE // "faster_whisper"' "$OPTIONS_FILE")
    ASR_COMPUTE_TYPE=$(jq -r '.ASR_COMPUTE_TYPE // "int8"' "$OPTIONS_FILE")
    WHISPER_LANG=$(jq -r '.WHISPER_LANG // "ja"' "$OPTIONS_FILE")
    WHISPER_TASK=$(jq -r '.WHISPER_TASK // "translate"' "$OPTIONS_FILE")
    ASR_PORT=$(jq -r '.ASR_PORT // "9001"' "$OPTIONS_FILE")
else
    echo "[Whisper ASR] No options.json found, using defaults..."
    ASR_MODEL="small"
    ASR_ENGINE="faster_whisper"
    ASR_COMPUTE_TYPE="int8"
    WHISPER_LANG="ja"
    WHISPER_TASK="translate"
    ASR_PORT="9001"
fi

export ASR_MODEL_PATH="/data/models"
export ASR_MODEL="${ASR_MODEL}"
export ASR_ENGINE="${ASR_ENGINE}"
export ASR_COMPUTE_TYPE="${ASR_COMPUTE_TYPE}"
export WHISPER_LANG="${WHISPER_LANG}"
export WHISPER_TASK="${WHISPER_TASK}"
export ASR_PORT="${ASR_PORT}"

echo "[Whisper ASR] Starting with:"
echo "  Model:        $ASR_MODEL"
echo "  Engine:       $ASR_ENGINE"
echo "  Compute type: $ASR_COMPUTE_TYPE"
echo "  Language:     $WHISPER_LANG"
echo "  Task:         $WHISPER_TASK"
echo "  Port:         $ASR_PORT"
echo "[Whisper ASR] ASR webservice will be available on port $ASR_PORT"

echo "[Whisper ASR] Checking entrypoint..."
cat /entrypoint.sh 2>/dev/null || echo "no entrypoint.sh"
ls / | grep -i entry 2>/dev/null
which uvicorn 2>/dev/null
which python3 2>/dev/null

exec /app/.venv/bin/uvicorn app.webservice:app --host 0.0.0.0 --port "${ASR_PORT}"
