#!/bin/bash
# serial-cmd.sh — Send a command to the BQ268 via USB serial and capture output
# Usage: serial-cmd.sh "command" [timeout_seconds]
set -e

TTY="${SERIAL_TTY:-/dev/ttyACM0}"
CMD="$1"
TIMEOUT="${2:-5}"

if [ -z "$CMD" ]; then
    echo "Usage: $0 'command' [timeout_seconds]" >&2
    exit 1
fi

if [ ! -e "$TTY" ]; then
    echo "ERROR: $TTY not found — device not booted?" >&2
    exit 1
fi

# Configure port
stty -F "$TTY" 115200 raw -echo -echoe -echok -onlcr 2>/dev/null

# Drain stale input
timeout 0.3 cat "$TTY" > /dev/null 2>&1 || true

# Start background reader
timeout "$TIMEOUT" cat "$TTY" &
READER=$!
sleep 0.3

# Send command
printf '%s\n' "$CMD" > "$TTY"

# Wait for reader to finish (timeout)
wait $READER 2>/dev/null || true
