# vpm: the vaporOS package manager

**Status: design, plus working code: versions, the pure-Lua filter and index builder, the resolver, the state
layer, the installer and the command line (`lib/vpm/`, `bin/vpm.lua`); it runs on a host Lua and on the RP2040.
HTTP(S) downloads and signed indexes work through vlr's `std.http`/`vapor.tls`/`vapor.sign`: vpm now runs on vlr only (vlua is gone). Run the tests with `tests/run.sh` (needs `vlr` on PATH or `VLR=...`); run vpm itself with `vlr /path/to/vpm <command>` (the folder has a manifest).** Started 2026-10-27. Everything here is a proposal until it appears in
[docs/decisions.md](docs/decisions.md).

vpm installs two kinds of things with one tool: **libraries** for your own Lua projects (what npm or luarocks
do) and whole **programs** with their dependencies, installed system-wide (what apt, dnf or portage do). On
vaporOS both are interpreted (Lua, shell), so one tool can do both, and it runs **on the device itself**: a
vaporOS machine must be able to fetch, resolve and install without a PC.

Inspirations: **npm** for the command line (short, memorable: `vpm i`, `vpm i -g`) and **portage** for being a
system package manager that works from sources, resolves dependencies itself, and keeps a "world" of what the
user asked for versus what was pulled in. Package data comes from **LuaRocks**, filtered to pure Lua.

## Goals

1. Works on the smallest officially supported target, the **RP2040 (about 187 KB free RAM, 24 KB task stack,
   ~1 MB of flash filesystem)**. Bigger targets may do more, but the basics must run on the RP2040.
2. **Pure Lua only.** Never fetch a rock that needs a compiler or a native library the firmware lacks.
3. **No copy of the world on the device:** one physical copy of a library when several programs share it.
4. **Honest dependency handling:** detect version conflicts, know which program uses which library, and show
   what an update would affect before doing it.
5. **Offline still works:** boards without networking just get files copied into `/usr/lib/lua` or
   `/flash/lib/lua`; vpm should understand and track those too.
6. **Same behaviour on the sim, on a board and (later) on a normal Linux/macOS/BSD host.**

## Non-goals (for now)

- Installing compiled code. Native libraries are firmware features chosen at build time.
- A sandbox for installed code. A package runs with the privileges of the program using it.
- Hosting our own package repository. We publish a small derived *index* (see docs), not the packages.

## Documents

| file | what |
|---|---|
| [docs/spec.md](docs/spec.md) | **the specification**: commands, paths, config, manifest, plan format, exit codes |
| [docs/design.md](docs/design.md) | concepts, commands, scopes, program/library kinds, the overall shape |
| [docs/dependency-resolution.md](docs/dependency-resolution.md) | versions, the resolver, the "global vs local" rules, a worked example |
| [docs/pure-lua-filter.md](docs/pure-lua-filter.md) | how we decide a rock is pure Lua, and where that is unsafe |
| [docs/state-and-tracking.md](docs/state-and-tracking.md) | on-disk layout, who uses what, update impact |
| [docs/index-and-network.md](docs/index-and-network.md) | the derived index, transport, TLS, how to test without a network board |
| [docs/ram-budget.md](docs/ram-budget.md) | what the RP2040 allows and how vpm stays inside it |
| [docs/vaporos-prerequisites.md](docs/vaporos-prerequisites.md) | things vaporOS itself must provide first (shebangs, http, sha256...) |
| [docs/open-questions.md](docs/open-questions.md) | what we have not decided |
| [docs/decisions.md](docs/decisions.md) | decision log (dated) |
