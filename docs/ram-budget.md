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

## Measured: installer on the RP2040-Zero (2026-10-27, `lib/vpm/*` as of the state/installer commit)

Test: `file://` mirror on the board's littlefs, 7 libraries in a diamond (11 files, 11 KB), resolve + install +
rehash + remove. Stripped bytecode, early-GC default of vlua unless noted.

| item | result |
|---|---|
| code, 8 modules | source 35 KB: 1.5 s to load, **84 KB of heap**. Stripped bytecode (built on the PC, loads fine on the ARM board: R4 answered) 25 KB file: 0.8 s, **53 KB of heap** |
| Lua heap during the whole run | 111 KB peak with the default GC; **152 KB with a relaxed GC** (200,100) |
| resolve, 7 packages | 1.56 s (0.61 s relaxed GC) |
| install, 7 packages / 11 files | **28.6 s** (25.4 s relaxed GC); hashing only ~1.6 s of it (7 KB/s pure Lua) |
| rehash check / remove | 4.2 s / 5.9 s |

Where the install time goes: **flash filesystem operations**, measured separately: create+write a 1 KB file
**298 ms**, rename **415 ms**, remove 130 ms, mkdir 114 ms, existence check 35 ms, read 30 ms. The first version
needed 34.4 s; removing repeated existence checks and mkdirs saved 17%. Stage-then-rename writes every file and
every record twice. The honest consequences:

1. Cost is per **file** (~0.3-0.9 s each), not per byte: a 40-file package takes ~30 s even if it is 100 KB.
   Pure-Lua rocks with many tiny files hurt most; packing a package into one file would be much faster.
2. The relaxed GC is faster but breaks the RAM budget (peak 152 KB vs the 100 KB hard limit), so it is not free.
3. Even at default GC the peak (111 KB, of which 53 KB is code) is above the 100 KB hard budget: load modules per
   command (`remove`/`list` need no resolver or network code) and make the hash loop produce less garbage.

