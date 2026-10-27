#!/bin/sh
# tools/deploy-board.sh [CONFIG]   build the distribution and copy it to the RP2040-Zero over the USB console.
# Needs the sibling vaporOS checkout (its rp2040 tools) and an idle board with /flash/recv.lua in place
# (see vaporOS tools/rp2040-send.py). Takes about 20 s per 10 KB.
set -e
cd "$(dirname "$0")/.."
VAPOROS=${VAPOROS:-../vaporOS}
CONFIG=${1:-config/rp2040.lua}
DIST=$(mktemp -d)
FLAT=$(mktemp -d)
trap 'rm -rf "$DIST" "$FLAT"' EXIT
lua tools/build-dist.lua "$DIST" "$CONFIG"
( cd "$DIST" && find . -type f | sed 's|^\./||' ) | while read -r f; do
  cp "$DIST/$f" "$FLAT/d--$(echo "$f" | sed 's|/|--|g')"
done
cp tools/vpm-unpack.lua "$FLAT/vpm-unpack.lua"
# The serial link stalls now and then: send file by file, give each a time limit, take the board out of
# recv.lua (it quits on "Q") after a stall, and retry.
unstick() {
  python3 -I - <<'PY'
import os, glob, termios, time, select
fd = os.open(glob.glob("/dev/ttyACM*")[0], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
t = termios.tcgetattr(fd); t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)
def drain(sec):
    buf = b""; end = time.time() + sec
    while time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try: buf += os.read(fd, 8192)
            except BlockingIOError: pass
    return buf
def send(b):
    for j in range(0, len(b), 64):
        while not select.select([], [fd], [], 1)[1]: pass
        os.write(fd, b[j:j+64]); time.sleep(0.012)
os.write(fd, b"\x03"); time.sleep(0.4)
# A transfer that stalled leaves recv.lua waiting for bytes, and then swallows "Q" as data: feed it dummy hex
# until it has all it wanted and reads the Q (the shell prompt comes back).
for i in range(120):
    send((b"00" * 100) + b"\r"); drain(0.05)
    if i % 10 == 9:
        send(b"Q\r")
        if b"vaporshell" in drain(0.8): break
time.sleep(0.5); drain(0.3)
PY
}
unstick
for f in "$FLAT"/*; do
  ok=
  for try in 1 2 3; do
    if timeout 90 python3 -I "$VAPOROS/tools/rp2040-send.py" "$f" >"$FLAT/.log" 2>&1 && grep -q " ok$" "$FLAT/.log"; then
      ok=1; echo "sent $(basename "$f")"; break
    fi
    echo "retry $try: $(basename "$f")" >&2; unstick
  done
  [ -n "$ok" ] || { echo "could not send $(basename "$f")" >&2; exit 1; }
done
python3 -I "$VAPOROS/tools/rp2040-stream.py" "$FLAT/.out" 'cd /flash; lua vpm-unpack.lua; rm vpm-unpack.lua' 60 >/dev/null || true
grep -a UNPACKED "$FLAT/.out" || { echo "unpack did not report success" >&2; exit 1; }
