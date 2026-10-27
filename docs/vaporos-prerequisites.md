# What vaporOS itself must provide first

vpm is a Lua program; some things it needs are firmware or shell features. Each is also useful on its own,
so they can be built before vpm exists. Order is roughly the order they unblock work.

| # | needed | why | where | state |
|---|---|---|---|---|
| P1 | **Shebang support for Lua (and sh) scripts**: `#!/usr/bin/env lua` / `#!/bin/lua` run by vaporshell | a program installed by vpm must be runnable by name from any path | vaporshell (or NuttX exec) | **done 2026-10-27** (vaporshell `platform_nuttx.c`; sim + RP2040 verified) |
| P2 | A **command directory on `PATH`** that vpm can drop launchers in (`/usr/bin`, `/flash/bin`) | `vpm i -g notes` then `notes` | vaporOS board config + vaporshell | **measured 2026-10-27:** `PATH` is *unset* in vaporshell on the board (the lookup falls back to `/bin` only, `platform_nuttx.c`), so `vpm` by name needs `PATH=/flash/sb:/bin` first. With it set, the launcher `#!/bin/lua` in `/flash/sb` works. vaporOS needs a default PATH or a startup file; `config/rp2040.lua` uses `/flash/sb` as `bindir` meanwhile. No symlinks on littlefs, so a launcher is a tiny script with a shebang, not a link |
| P3 | **sha256** (and crc32) as a built-in: `vapor.sha256(string)` plus an incremental form | integrity of downloads | vlua C code (NuttX has crypto/mbedtls pieces; a 2 KB standalone implementation is also fine) | not started |
| P4 | **HTTP(S) client** reachable from Lua, streaming: `vapor.http.get(url, sink)` | download from a running device | NuttX netutils webclient or sockets + mbedTLS; wrapped in vlua | not started; needs R1/R2 |
| P5 | **Directory and file primitives vpm relies on**: atomic rename, mkdir -p, recursive remove, file size, free space (`statfs`) | stage-then-rename install, space check | already mostly in lfs/os; `statfs` and `rename` semantics on littlefs and hostfs to be verified | partly verified |
| P6 | **`luac`-equivalent on the device** (`string.dump(load(src), true)`) for bytecode install | smaller/faster installs | already in the Lua standard library; verify stripping works with our build | easy |
| P7 | **A "provided libraries" table** the runtime exposes: name, version, rock name | the resolver must know lfs/lpeg/cjson and their versions | vlua: `package.loaded`/`vapor.provided`, generated at build time | not started |
| P9 | **A `compat53` stub**: `package.preload.compat53 = function() return true end` in the runtime | 28+ rocks list compat53 as a dependency; it does nothing on Lua >= 5.3 | vlua | not started, trivial |
| P10 | **A socket library** (luasocket-compatible subset: `socket`, `socket.url`, `socket.http`...) | blocks 179 rocks, and vpm itself needs HTTP | firmware (vlua) | not started; see index-and-network.md |
| P11 | **System heap figures from Lua**: `/proc/meminfo` already exists on the board (`total used free maxused maxfree`; `maxused` is the high-water mark since boot, so a reboot before a run gives the peak of that run) | measuring the real free heap of a vpm run | works today, nothing to build | verified 2026-10-27 |
| P8 | **Wall-clock time** (`os.time`) correct enough for records | install dates, cache freshness | works; RTC absent on RP2040 so dates are not real until set | note |

## Bash/Lua parity

Official languages are bash-like (vaporshell) and Lua. A shell program (`lang = "sh"`) is installed the same
way and needs only P1/P2.

## Not needed (checked)

- zlib/tar on the device: the index lists individual files ([index-and-network.md](index-and-network.md)).
- Symlinks: not used.
- Dynamic loading: not possible and not wanted; native libraries are firmware features.

## Status of P4 / P10 on the simulator (2026-10-27)

The simulator now has real networking, which is how vpm fetches from LuaRocks sources today:

- **P10 (sockets):** `require("vsock")` (vaporOS `vlua/vsock.c`): `connect/send/recv/close`, polled non-blocking TCP.
  The simulator's usrsock bridge needed two things: the custom transport (`NET_USRSOCK_CUSTOM`) and a patch,
  `sim-usrsock-event-loop` (upstream regression, nothing was ever received). `hardware/network/sim-usrsock.conf`.
- **P4 (HTTPS):** `require("vtls")` (`vlua/vtls.c`, mbedTLS 3.6, TLS 1.2): certificate **and** host name are always
  verified against a PEM bundle (`cafile` in the vpm config). Checked: an expired and a wrong-host certificate are
  rejected, GitHub raw files and luarocks.org are fetched. The HTTP/1.1 client itself is Lua (`lib/vpm/http.lua`).
  It needed a secure entropy source, so the sim got `/dev/random` and `/dev/urandom` backed by the host
  (`sim-dev-random-host` patch), a 256 KB vlua stack and 40 nested C calls (`boards/sim-nsh/board.conf`).
- **Not yet:** the real board. Nothing here is sized for 264 KB: the CA bundle is 185 KB of PEM, a TLS handshake
  wants tens of KB of heap on top of vpm's 121 KB peak, and only the Pico W has a radio. Next: measure on the sim with
  `/proc/meminfo`-like counters, then decide how much of this the RP2040 can carry (a trimmed bundle with the 3-4 roots
  GitHub and luarocks need, or plain HTTP to a nearby mirror with signed index entries; see index-and-network.md).
- CA bundle on the simulator: copied by hand (`tools/sim-vpm.sh` does it) from the host; a sim feature that exposes it
  without a copy is still to do.
- Known index gap: 11 packages have no download URL (luaunit among them); `vpm install` refuses them with a message.

