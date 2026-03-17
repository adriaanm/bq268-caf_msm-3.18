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

exec python3 -c "
import os, termios, time, select, sys

fd = os.open('$TTY', os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[4] = attrs[5] = termios.B115200
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[6][termios.VMIN] = 0
attrs[6][termios.VTIME] = 5
termios.tcsetattr(fd, termios.TCSANOW, attrs)
termios.tcflush(fd, termios.TCIOFLUSH)
time.sleep(0.2)

# Send command
cmd = '''$CMD''' + '\n'
os.write(fd, cmd.encode())
time.sleep(0.5)

# Read until timeout
deadline = time.time() + $TIMEOUT
data = b''
while time.time() < deadline:
    if select.select([fd], [], [], 0.5)[0]:
        try:
            chunk = os.read(fd, 8192)
            if chunk:
                data += chunk
                # If we see the next prompt, we're done
                if b'# ' in chunk and len(data) > len(cmd) + 10:
                    break
        except BlockingIOError:
            pass
    else:
        if data:
            break

os.close(fd)

lines = data.decode('utf-8', errors='replace').splitlines()
# Skip the echo of our command and trailing prompt
for line in lines:
    line = line.rstrip()
    if line and not line.endswith('# ') and not line.startswith(cmd.strip()):
        sys.stdout.write(line + '\n')
"
