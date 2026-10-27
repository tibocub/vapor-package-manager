#!/bin/sh
# tools/sim-vpm.sh [-i INDEX_DIR] VPM-ARGS...   run vpm inside the NuttX simulator (../nuttx/nuttx) with network access.
#   -i DIR   serve DIR (containing index/v1) on http://127.0.0.1:8099 for the run (the files it lists are fetched from
#            their real https URLs, verified against the CA bundle)
# VPM_KEYS="hex hex" makes vpm require ed25519 signatures on the index (docs/signing.md)
# The simulator's global library directory is a host directory (sim dir/vaporos-lua = /usr/lib/lua); the sim dir is
# $SIMDIR (default: a fresh temp dir, kept so you can look at what vpm installed). Needs the sim-nsh build of vaporOS.
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
NUTTX=${NUTTX:-$HERE/../nuttx/nuttx}
CA=${CA:-/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem}
SIMDIR=${SIMDIR:-$(mktemp -d)}
INDEX=
KEYS=; [ -n "$VPM_KEYS" ] && KEYS=", keys = { $(for k in $VPM_KEYS; do printf '"%s", ' "$k"; done) }"
[ "$1" = "-i" ] && { INDEX=$2; shift 2; }
mkdir -p "$SIMDIR/vaporos-lua"
rm -rf "$SIMDIR/vaporos-lua/vpm"; cp -r "$HERE/lib/vpm" "$SIMDIR/vaporos-lua/vpm"
cp "$CA" "$SIMDIR/vaporos-lua/ca.pem"
cat > "$SIMDIR/vaporos-lua/vpmrun.lua" <<LUA
local f = io.open("/usr/lib/lua/vpm-sim-config.lua", "w")
f:write([[return { libdir = "/usr/lib/lua", appdir = "/usr/lib/lua/apps", bindir = "/usr/lib/lua/bin",
  index = "http://127.0.0.1:8099/index/v1", cafile = "/usr/lib/lua/ca.pem", reserve = 0, profile = "full"$KEYS }]])
f:close()
os.exit(require("vpm.cli").main({ "--config=/usr/lib/lua/vpm-sim-config.lua", table.unpack(arg) }, {}))
LUA
if [ -n "$INDEX" ]; then
  (cd "$INDEX" && exec python3 -I -m http.server 8099 --bind 127.0.0.1 >/dev/null 2>&1) &
  SERVER=$!
  trap 'kill $SERVER 2>/dev/null' EXIT
  sleep 1
fi
echo "sim dir: $SIMDIR" >&2
cd "$SIMDIR"
# nsh reads the commands from stdin; "poweroff" ends the simulator. vpm's exit status is printed as RC=n.
( printf 'lua /usr/lib/lua/vpmrun.lua %s; echo RC=$?\n' "$*"; sleep "${WAIT:-60}"; printf 'poweroff\n'; sleep 1 ) |
  timeout $(( ${WAIT:-60} + 20 )) "$NUTTX" 2>&1 | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -d '\r' | grep -av '^$'
