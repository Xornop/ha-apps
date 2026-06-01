#!/bin/bash
echo "==============================================="
echo "[SubGen Addon] run.sh is executing!"
echo "==============================================="

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    WHISPER_MODEL=$(jq -r '.WHISPER_MODEL // "small"' "$OPTIONS_FILE")
    COMPUTE_TYPE=$(jq -r '.COMPUTE_TYPE // "auto"' "$OPTIONS_FILE")
    TRANSCRIBE_DEVICE=$(jq -r '.TRANSCRIBE_DEVICE // "cpu"' "$OPTIONS_FILE")
    CONCURRENT_TRANSCRIPTIONS=$(jq -r '.CONCURRENT_TRANSCRIPTIONS // "1"' "$OPTIONS_FILE")
    WHISPER_THREADS=$(jq -r '.WHISPER_THREADS // "4"' "$OPTIONS_FILE")
    TRANSCRIBE_OR_TRANSLATE=$(jq -r '.TRANSCRIBE_OR_TRANSLATE // "translate"' "$OPTIONS_FILE")
    SKIP_LANGUAGE_DETECT=$(jq -r '.SKIP_LANGUAGE_DETECT // "true"' "$OPTIONS_FILE")
    WEBHOOKPORT=$(jq -r '.WEBHOOKPORT // "9000"' "$OPTIONS_FILE")
    DEBUG=$(jq -r '.DEBUG // "false"' "$OPTIONS_FILE")
else
    WHISPER_MODEL="small"
    COMPUTE_TYPE="auto"
    TRANSCRIBE_DEVICE="cpu"
    CONCURRENT_TRANSCRIPTIONS="1"
    WHISPER_THREADS="4"
    TRANSCRIBE_OR_TRANSLATE="transcribe"
    SKIP_LANGUAGE_DETECT="true"
    WEBHOOKPORT="9000"
    DEBUG="false"
fi

# Write subgen.env so SubGen picks it up automatically
cat > /subgen/subgen.env << EOF
WHISPER_MODEL=${WHISPER_MODEL}
COMPUTE_TYPE=${COMPUTE_TYPE}
TRANSCRIBE_DEVICE=${TRANSCRIBE_DEVICE}
CONCURRENT_TRANSCRIPTIONS=${CONCURRENT_TRANSCRIPTIONS}
WHISPER_THREADS=${WHISPER_THREADS}
TRANSCRIBE_OR_TRANSLATE=${TRANSCRIBE_OR_TRANSLATE}
SKIP_LANGUAGE_DETECT=${SKIP_LANGUAGE_DETECT}
WEBHOOKPORT=${WEBHOOKPORT}
MODEL_PATH=/data/models
PROCADDEDMEDIA=false
PROCMEDIAONPLAY=false
USE_PATH_MAPPING=false
DEBUG=${DEBUG}
EOF

echo "[SubGen] Written subgen.env with settings:"
cat /subgen/subgen.env
echo "[SubGen] Looking for subgen.env, checking locations:"
find / -name "subgen.env" 2>/dev/null
echo "[SubGen] SubGen working directory:"
ls /subgen/
cd /subgen && exec python3 /subgen/launcher.py
