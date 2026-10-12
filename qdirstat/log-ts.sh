#!/bin/sh
# Zet een timestamp voor elke logregel; /init blijft PID 1 (exec).
FIFO=/run/log-ts.fifo
rm -f "$FIFO"
mkfifo "$FIFO"

(
    while IFS= read -r line; do
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"
    done < "$FIFO"
) &

exec /init "$@" > "$FIFO" 2>&1
