# The index, transport and testing without a network board

## Why a derived index, and why this is not "our own repository"

The device cannot use LuaRocks' data directly:

- The LuaRocks manifest is a multi-megabyte Lua file. It does not fit in 187 KB of heap, and parsing it would
  mean executing it.
- Rock dependencies, build type and sources live in rockspecs, which are *code*. Deciding "pure Lua" needs the
  evaluation and archive inspection described in [pure-lua-filter.md](pure-lua-filter.md).

So a publisher (a PC or CI job, run by us or anyone) builds a **derived index** from LuaRocks and publishes it
as static files. The *packages themselves still come from their upstream sources* (the rock's git/tarball
URL, hash-pinned in the index). We maintain a filter and a data format, not a package collection.

## Sparse layout: one small file per package

Same idea as cargo's sparse registry: the client fetches only the files for packages it is resolving.

```
index/v1/
  meta.json                     format version, build date, Lua version, provided-library table used
  p/ar/argparse.json            all accepted versions of "argparse"
  p/pe/penlight.json
  search/…                      small prefix files for `vpm search` (optional; may be absent on the RP2040)
```

A package file (JSON, decoded with the firmware's cjson, because remote data must never be `load`ed as code).
**This is the format `index-builder/build.lua emit` writes today** (`deps` are the rockspec strings, `lua` is the
constraint on Lua itself; `host` and `undeclared_requires` are present only when set):

```json
{ "name": "argparse", "kind": "lib",
  "versions": {
    "0.7.2-1": {
      "lua": ">= 5.1",
      "deps": [],
      "modules": ["argparse"],
      "files": { "argparse.lua": { "sha256": "…", "size": 78125,
                                   "url": "https://raw.githubusercontent.com/…/<commit-or-tag>/src/argparse.lua" } },
      "bin": {},
      "origin": { "type": "archive", "url": "https://github.com/…/archive/….tar.gz", "sha256": "…" },
      "summary": "…", "license": "MIT", "homepage": "…"
    } } }
```

Listing every file with its own URL and hash means the device **never needs to unpack an archive** (no zlib
or tar on a 187 KB machine) and can stream each file straight to flash. The index builder does the archive
work on the PC and resolves each file to a stable raw URL pinned to a commit/tag (or to a mirror, open
question). Files larger than a configurable limit are refused on small targets.

Size estimate: typical package file 1–4 KB; a resolution touching 8 packages downloads under 30 KB of
metadata. The whole index for pure-Lua rocks is expected to be a few MB on the server, nothing on the device.

## Trust

1. `meta.json` and package files are served over HTTPS.
2. Every installed file is checked against its sha256 from the index. The index itself should later be signed
   (an ed25519 public key shipped in vpm; open question). Without signing, trust = the TLS connection to the
   index host.
3. Upstream files are pinned by hash in the index, so a changed upstream is detected, not silently installed.

## Transport

vpm talks to a small `transport` interface so everything above it is testable offline:

```
transport.get(url, sink)   -- stream the body to sink(chunk); returns status
transports: file://  (a directory, an SD card, a USB-mounted folder)
            http://  https://   (needs the vaporOS network and TLS pieces)
```

`file://` makes **offline install** a first-class case: a PC (or another vaporOS) can export a *mirror
directory* with the same layout as the index plus the files, and a board without networking installs from an
SD card with the same command (`vpm --index file:///sd/mirror i notes`).

## TLS on a small board: a real risk, stated plainly

HTTPS needs a TLS 1.2/1.3 handshake. NuttX supports mbedTLS, but a handshake wants tens of KB of heap on top
of the network stack, and certificate validation needs a CA bundle in flash. On a Pico W (264 KB RAM, same
as the RP2040) it is plausible but not proven here. Fallbacks, in order of preference:

1. TLS with a pinned small set of CA roots (only the index host and its file host),
2. plain HTTP to the index with end-to-end integrity from a **signed index + sha256 per file** (integrity
   without confidentiality; acceptable for public packages once signing exists),
3. a local relay on the user's network.

This must be measured on a real Pico W before the design depends on it (research item R1).

## Testing without a network board

The user has no networked board yet. Plan:

1. **Resolver and state logic** run on any host Lua and on the sim with a *fake index* (tables in a file);
   no network at all. This is most of the code.
2. **`file://` transport** on the sim and on the board: exercises download, hashing, staging, install and
   uninstall from a folder. Needs only the filesystem.
3. **HTTP on the sim**: the NuttX simulator can reach the host network in some configurations (a TAP
   interface or the usrsock host-socket bridge). Which one works for vaporOS-sim, and what it needs
   (root, extra config), is **unverified**. Research item R2. Until then, HTTP is tested by the same code
   paths as `file://` plus unit tests of the HTTP framing against recorded responses.
4. A throwaway HTTP server on the PC (`python3 -m http.server`) serving a mirror directory, once R2 is solved.
5. TLS is tested only when a Pico W/ESP32 arrives (R1).

## Index publishing

The index builder (a Lua script under `vpm/index-builder/`, run on a PC or in CI) fetches LuaRocks' manifest,
applies the filter, resolves files, and writes `index/v1/…`. Hosting target: static hosting (e.g. GitHub Pages
or any web server); a second mirror is a copy of the directory. Nothing runs on a server except file serving.

## Blobs, host tags and retries (2026-11-22)
- **Blobs:** files of rocks whose source is an archive on an arbitrary host have no stable per-file URL. The builder (`VLR_BLOBS=dir` for the `one` stage and `emit`) keeps them as
  content-addressed files `blobs/aa/<sha256>` served next to `index/`; the package entry says `"url": "blob:<sha256>"` and the installer resolves it against the index base
  (`<root>/blobs/aa/<sha256>`, root = index base without `/index/v1`). The signed package file covers the hash, and every file is hash-checked, so the host needs no trust.
  The first full run: 231 rocks, 4,245 blobs, 141 MB (some rocks ship large data files: a size policy for the index is still to decide).
- **Host tags:** `emit` tags a rock `host = "luajit" | "nvim" | "openresty" | "awesome" | "love"` from the filter's tag or what its code requires (`ffi`/`jit`, `vim`, `ngx`/`resty`/`kong`,
  `awful`/`gears`/..., `love`). vpm hides tagged versions unless the config says `hosts = { "luajit" }` etc.; the error then names the host.
- **Retries:** the installer repeats a download after 429, 5xx, 408/425 or a network timeout (up to 4 attempts, waits 1, 3, 9 s plus jitter), each attempt with a fresh file and hash.
  Certificate failures and 404 are never retried. Shortcut: `Retry-After` is ignored.
