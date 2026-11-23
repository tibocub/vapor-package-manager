# vpm: a package manager for Lua

vpm installs **libraries** (into a project, like npm, or system-wide) and **programs** (with their dependencies) from the whole of
[luarocks.org](https://luarocks.org), on any machine that runs [vlr](../vlr): Linux, macOS, Windows, a Raspberry-Pi-class board or a
vaporOS device. vlr + vpm is meant to be to Lua what Python + pip or Node + npm are to theirs. vaporOS is one platform vpm runs on, not the
only one: the same tool runs on the RP2040 (about 187 KB free RAM) and on a desktop.

```
vpm search json --here --works     what can I install here, and is known to run on vlr?
vpm info lua-cjson                 versions, dependencies, native class, "can be installed on this machine"
vpm i                              install what vpm.lua asks for, exactly as locked in vpm-lock.lua
vpm i lpeg@1.1                     add a library (project: ./lua_modules, or -g for the whole system)
vpm rm / ls / why / check          remove, list, who needs this, verify files
```

## What it knows about every rock

Nothing is hidden: the index lists every rock and **says what it takes**.
- **pure** Lua: files are copied.  **c**: only C code, built with the machine's C compiler against vlr's own headers (`vpm` checks the source rock's sha256, compiles, installs the `.so`).
  **build** (make, cmake, a build plugin) and **other** (C++, Rust, ...) are listed and described; building those is not supported yet.
- written for a **host** (Neovim, OpenResty, LÖVE, awesome, LuaJIT): shown with a note; `--host=` / `--no-host` narrow the search.
- **works with vlr**: the index builder loads each rock in a sandbox on vlr and records the result (`vlr:ok`, `partial`, `fails`); `search --works` filters on it.
- `--here` filters to what *this* machine can install (is there a compiler, tar/unzip, dlopen?).

## Where the index lives

The public index is served by GitHub Pages from [tibocub/vpm-index](https://github.com/tibocub/vpm-index): `https://tibocub.github.io/vpm-index/index/v1`. vpm uses it (and its public key) by default when there is no config file; installs go to `~/.local/share/vpm` (`-g`) or `./lua_modules`. `tools/publish-index.sh` publishes a rebuilt index only after `tools/check-index.lua` has verified every signature, blob and catalogue line.

## Trust

vpm reads **luarocks.org**. Our index is a signed (ed25519) **mirror of hashes and dates** for every rock (rockspec, source rock, each file of the pure ones), so a download over plain HTTP
is still verified, and so a rock cannot silently change under a version you locked. `vpm-lock.lua` records exact versions and an integrity digest per package; a plain `vpm i` follows it and refuses
when the bytes changed.

## State of the code

Working: versions, the resolver, the transactional installer (journal, staging, retries), signed indexes, search/info, the lock file, host/native/compat notes, building C rocks. Runs on vlr only.
Not done: building make/cmake/other rocks, publishing (planned through luarocks.org's upload API), a Windows round for the native builds, archives on boards (pure rocks install file by file there).
See [docs/decisions.md](docs/decisions.md) for the dated decisions and [docs/native-detection.md](docs/native-detection.md), [docs/luarocks-source.md](docs/luarocks-source.md) for the index.

## Documents

| file | what |
|---|---|
| [docs/spec.md](docs/spec.md) | **the specification**: commands, paths, config, manifest, plan format, exit codes |
| [docs/design.md](docs/design.md) | concepts, commands, scopes, program/library kinds, the overall shape |
| [docs/dependency-resolution.md](docs/dependency-resolution.md) | versions, the resolver, the "global vs local" rules, a worked example |
| [docs/pure-lua-filter.md](docs/pure-lua-filter.md) | the original pure-Lua filter (history; native rocks are now classified, see native-detection) |
| [docs/native-detection.md](docs/native-detection.md) | pure / c / build / other, how it is detected and how the detector was checked |
| [docs/luarocks-source.md](docs/luarocks-source.md) | luarocks.org as the source, the signed hash mirror, source rocks |
| [docs/state-and-tracking.md](docs/state-and-tracking.md) | on-disk layout, who uses what, update impact |
| [docs/index-and-network.md](docs/index-and-network.md) | the derived index, transport, TLS, how to test without a network board |
| [docs/ram-budget.md](docs/ram-budget.md) | what the RP2040 allows and how vpm stays inside it |
| [docs/vaporos-prerequisites.md](docs/vaporos-prerequisites.md) | things vaporOS itself must provide first (shebangs, http, sha256...) |
| [docs/open-questions.md](docs/open-questions.md) | what we have not decided |
| [docs/decisions.md](docs/decisions.md) | decision log (dated) |
