#!/bin/sh
# tools/deploy-board.sh [CONFIG]   build the distribution and copy it to the RP2040-Zero over the USB console.
# Uses the sibling vaporOS checkout's tools/rp2040-put.py: slow (about 100 B/s, 47 KB is ~8 minutes) but flow
# controlled, retried and md5-checked per file. The faster rp2040-send.py streams hex without any handshake, and
# the RP2040 stops serving USB while it programs flash, so it loses data and leaves the board's recv.lua waiting
# for bytes (measured 2026-10-27: it stalled in every long run) -- do not use it for more than a few KB.
set -e
cd "$(dirname "$0")/.."
VAPOROS=${VAPOROS:-../vaporOS}
CONFIG=${1:-config/rp2040.lua}
DIST=$(mktemp -d); OUT=$(mktemp)
trap 'rm -rf "$DIST" "$OUT"' EXIT
lua tools/build-dist.lua "$DIST" "$CONFIG"
# directories first (the shell's mkdir; existing ones are fine)
DIRS=$( ( cd "$DIST" && find . -type d | sed 's|^\./||' | grep -v '^\.$' ) | sort | while read -r d; do printf 'mkdir /flash/%s; ' "$d"; done)
python3 -I "$VAPOROS/tools/rp2040-stream.py" "$OUT" "$DIRS true" 30 >/dev/null || true
PAIRS=$( ( cd "$DIST" && find . -type f | sed 's|^\./||' | sort ) | while read -r f; do printf '%s /flash/%s ' "$DIST/$f" "$f"; done)
# shellcheck disable=SC2086
python3 -I "$VAPOROS/tools/rp2040-put.py" $PAIRS
