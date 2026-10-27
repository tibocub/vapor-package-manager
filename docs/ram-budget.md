# Staying usable on the RP2040

## Measured facts (vaporOS, 2026-10-27, RP2040-Zero)

- Total heap 242 KB; **54 KB used on a fresh boot** with nothing running.
- Task stacks come from the heap: each command in a vaporshell pipeline costs ~10 KB while it runs.
- The `lua` task has a **24 KB stack**; deep recursion is capped (C-call depth 40). A recursive resolver written
  naively can hit it, so recursion depth must be bounded by the dependency depth and each frame kept small.
- A Lua state with lfs+lpeg+cjson loaded takes 17-20 KB; compiling a 50 KB source file in one go **does not
  fit**. Keep every vpm source file small (a few KB each, loaded lazily) or ship precompiled bytecode.
- Early garbage collection is on (`lua_gc(L, LUA_GCINC, 100, 400)`), which trades CPU for RAM.
- Flash filesystem about 1 MB (littlefs); free heap after boot about 187 KB.

## Budget

| item | limit |
|---|---|
| peak Lua heap during `vpm i` | **60 KB** target, 100 KB hard |
| per-package metadata held at once | one package file (a few KB) + the resolver's tables |
| download buffer | 1-2 KB chunks, streamed to a file; never a whole file in memory |
| code | split into modules loaded on demand (`vpm i` does not load `search`) |
| any single source file | under 8 KB |

## Techniques

1. **Stream, never buffer.** Network chunk -> hash update -> file write. One file at a time.
2. **Sparse index** ([index-and-network.md](index-and-network.md)): fetch metadata for the closure only.
3. **Records are tiny files** loaded one at a time ([state-and-tracking.md](state-and-tracking.md)); reverse
   dependencies are computed by a streaming scan, not kept.
4. **Free early:** the resolver drops metadata of packages once chosen unless a later backtrack needs it
   (rarely); `collectgarbage()` between phases is acceptable.
5. **Precompiled, stripped bytecode for vpm itself** once a `luac` step exists (also saves compile RAM);
   source otherwise.
6. **SHA-256 in C** inside the firmware (`vapor.sha256`), because pure-Lua SHA-256 costs thousands of VM
   instructions per 64-byte block on a 133 MHz Cortex-M0+ (our integer loop does ~120k steps/s), so hashing a
   40 KB file would take a minute or more; a CRC32 can be a stopgap. See
   [vaporos-prerequisites.md](vaporos-prerequisites.md).
7. **No JSON of the whole index:** cjson decodes one small file at a time.

## What is allowed to be missing on the RP2040

`vpm search` (needs the search shards), `--deps=auto` heuristics beyond the basic rule if too heavy, update
impact reports for very large installed sets, bytecode precompilation (needs `luac`). The core: `i`, `i -g`,
`rm`, `ls`, `why`, `up`, `check`, offline install from `file://`, must run on the RP2040.

## Measuring

Part of the first code milestone: a benchmark script that installs a synthetic 20-package closure from a
`file://` mirror and reports peak `collectgarbage("count")`, `free` and time, run on the sim and the RP2040.
The budgets above are guesses until that exists.
