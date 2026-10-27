# Keeping only pure-Lua rocks

Goal: use the LuaRocks repository without ever offering something that cannot work on vaporOS (no dynamic
linking, no compiler on the device).

## Where the filter runs

Not on the device. LuaRocks' manifest has thousands of rocks, and a rockspec is Lua *code* that has to be
evaluated to be understood. The filter runs on a PC or in CI, periodically, and produces the small derived
index the device reads ([index-and-network.md](index-and-network.md)). The device never evaluates a rockspec.
The index builder is a plain Lua script, so it can be run by anybody (including on vaporOS-sim).

This is the only part of vpm that needs a PC, and it is a *publisher* concern, not a user one.

## Rules (a rock is accepted only if every one holds)

For each rockspec of each version, evaluated in an empty sandboxed environment:

| # | rule | why |
|---|---|---|
| 1 | `build` is absent, or `build.type == "none"`, or `"builtin"` | other types (`make`, `cmake`, `command`, `cargo`...) run arbitrary build steps |
| 2 | every entry of `build.modules` is a **string ending in `.lua`**, or a table whose only sources are `.lua` | a module with `.c`/`.cpp`/`.h` sources or `libraries` is native |
| 3 | no `external_dependencies` | those are system C libraries |
| 4 | no `build.libraries`, `build.defines`, `build.incdirs`, `build.libdirs` | native build knobs |
| 5 | `build.platforms` / `build_dependencies` do not introduce native pieces | same |
| 6 | the `lua` dependency constraint admits 5.4 (e.g. `lua >= 5.1`, `lua ~> 5.4`) | the runtime is 5.4 |
| 7 | every other dependency is itself accepted, **or provided by the firmware** at a fitting version | transitive purity; this is why the index builder needs the provided list |
| 8 | **what the rock installs** (computed from `build.modules`, `install.lua`, `install.bin`, or LuaRocks' `src`/`lua`/`lib` auto-detection) is all `.lua`: no `.c` file in the auto-detected directories, every file exists, is a regular non-symlink file, is under 1 MB and **parses as Lua 5.4** | what is installed is what matters: a stray `.c` file elsewhere in the repository is never built or installed (my first draft wrongly scanned the whole tree) |
| 9 | `require` calls in installed files are scanned: modules that are neither the rock's own, the standard library, the firmware's, nor provided by its dependency closure are recorded as `undeclared_requires`; `ffi`/`jit` use sets `luajit` | a **warning**, not a rejection: many are optional (`pcall(require, ...)`) |
| 10 | the source is fetchable without a build step (git tag, tarball or zip with a stable URL) | needed to compute hashes |
| 11 | the rock is not written for a host application (Neovim, OpenResty/Kong, LÖVE, game engines): detected from its name, `description.labels` and dependencies | pure Lua, but needs an API vaporOS does not have; **found necessary by the first run** (see below) |

`install.bin` entries are fine if they are Lua scripts; they turn the rock into a *program* candidate.

## Overrides

A small curated file in the index repo can force-allow or force-deny a rock by name and version, with a reason.
The heuristic will be wrong sometimes; the override file is how it gets fixed without changing code.

## Known limits (be honest about them)

- Rules 2, 8 and 9 are heuristics. A rock can be pure Lua syntactically but *use* a native module at runtime
  (`require "socket"` inside code, undeclared in dependencies). Rule 7 catches declared dependencies only.
  Mitigation: run `luac -p` over every file at index time (syntax), and mark rocks whose source contains
  `require` of a name that is neither stdlib, provided, nor a declared dependency as "suspect" and hide them.
- Many popular rocks ARE native (luasocket, luasec, lpeg itself, lfs itself, lua-cjson...). That is expected;
  several are exactly what the firmware provides.
- Rocks written for Lua 5.1 only may use `setfenv`, `unpack`, `loadstring`. Rule 6 trusts the declared
  constraint. A compatibility shim (`compat53`) is itself pure Lua and is a legitimate dependency.
- A rockspec's `source.url` may point to a host that no longer exists. Index builds record the hash, and the
  index keeps a mirror copy of the file list only if needed (open question).
- Evaluation of a rockspec in a sandbox must be time- and memory-limited (a rockspec is untrusted code).

## Result per rock

The index stores accepted rocks only, plus (for `vpm info`) a one-line reason for popular rejected ones, so
that "why can't I install X?" has an answer: *"luasocket: native code (src/*.c)"*.

## Measured results (2026-10-27, implemented in `index-builder/`)

Run on the LuaRocks `manifest-5.4` (4,929 rocks, 33,294 versions), **latest release of each rock only**,
rules 1-7 and 11 (rules 8-9 need the source archives and are not implemented yet, so the numbers are an upper
bound). Fetching the 4,929 rockspecs took about 5.5 minutes with 8 parallel connections; the filter itself takes
under a second. Reproduce: `lua index-builder/run.lua list MANIFEST`, `index-builder/fetch.sh LIST DIR`,
`lua index-builder/run.lua report MANIFEST DIR`.

| outcome | rocks | share |
|---|---|---|
| **accepted** (pure Lua, dependencies ok) | **1,663** | **33.7%** |
| host-application API (Neovim 497, OpenResty/Kong 604, LÖVE 11, games 1) | 1,113 | 22.6% |
| native source in `build.modules` | 365 | 7.4% |
| depends on a rejected rock (root cause: native 359, build type 167, external lib 87, missing 34, host API 20) | ~675 | 13.7% |
| build type `treesitter-parser` (all native) | 343 | 7.0% |
| build type `make`, `command`, `hooks`, `cmake`, `l3build`, `rust-*`, others | ~600 | 12% |
| external C libraries | 169 | 3.4% |
| rest (`install.lib`, Lua version, bad data, rockspec missing) | ~20 | 0.4% |

What this told us:

1. **"Pure Lua" does not mean "usable".** Without rule 11, 2,594 rocks (52.6%) would have been offered, and
   1,113 of them are plugins for software that is not on vaporOS. Rule 11 is data-driven (name, label and
   dependency patterns in `filter.lua`) and will need curating; a label match like `love` can misfire, so a
   flagged rock should be hidden by default and installable with an explicit override, not removed.
2. **Sanity check passes:** penlight, argparse, inspect, dkjson, luaunit, serpent, middleclass, lustache, etlua,
   lunajson, classic, say, luassert are accepted. lpeg, lfs and lua-cjson are correctly *not* downloadable
   (native); the firmware provides them, and they are the most common dependencies among accepted rocks
   (lpeg 64, lua-cjson 54, luafilesystem 52), which confirms the choice of built-in libraries.
3. **Highest-leverage native additions** (rocks that block the most dependents): **luasocket blocks 179**,
   luasystem 38, compat53 28, luaposix 17, luasec 17, luv 14. A socket library in the firmware (needed anyway
   for networking) would unlock more than any other single item. `compat53` is only a shim for Lua < 5.3 and
   should be declared as a provided no-op package for 5.4.
4. Not covered yet: older versions of rocks whose latest version is rejected, rules 8-9, and the transitive
   case where a rock needs a module it does not declare.

## Source stage (implemented 2026-10-27)

`lua index-builder/build.lua one NAME VERSION SPECS WORK RECORDS` fetches one rock safely (git over https only
with `--depth 1` and the rock's tag, or an https archive with a size cap; `file://` and ssh sources are refused;
extraction is confined to a scratch directory), works out the installed files and hashes them
(`sha256sum`), checks them (rule 8-9) and writes a record. `build.lua todo` lists rocks without a record,
`build.lua emit` re-applies the dependency closure (a rock rejected at the source stage also removes its
dependents) and writes `index/v1/` (see [index-and-network.md](index-and-network.md)). About 8 rocks per second
with 8 parallel jobs; the full set (2,605 rocks) took about 6 minutes plus 5.5 for the rockspecs.

Result (latest release of each rock, 2026-10-27):

| outcome | rocks |
|---|---|
| **in the index** | **1,939** (39.3% of 4,929), of which 776 tagged for a host application (Neovim/OpenResty/LÖVE) |
| rejected at the rockspec stage (native, build type, external libs...) | ~2,000 |
| rejected at the source stage: download failed (dead repo, timeout) | 154 |
| source URL not usable (`file://` paths on someone's disk, ssh) | 152 |
| `source.tag` does not exist in the repository | 133 |
| native source found by auto-detection | 5 more (437 in total) |
| installed files do not parse as Lua 5.4 (written for 5.1 syntax) | 23 |
| rejected because a dependency was rejected | 909 |

The index holds ~15,700 files in 1,929 package files (the latest run, after the dependency closure and removing
URLs with credentials). Raw-file URLs are computed at emit time from the recorded origin and per-file source path
(`source.raw_url`), so the rules can change without re-fetching. Rules exist for GitHub, GitLab-style forges
(gitlab.com, framagit), Codeberg and a few Gitea hosts, sr.ht, gitee, bitbucket and GitHub archive URLs.
`index-builder/verify.lua` downloads a random sample from every host and compares sha256: 57 files, 0 mismatches.
Two Gitea hosts (code.tjp.lol, git.offblast.org) answer 403 to scripts, so their URLs cannot be verified and are
omitted. **11 packages have no downloadable file URL** (private hosts such as dkjson's); they need a mirror (Q8).
Credentials found in a source URL (a rockspec with an access token in it) cause the source to be refused, never copied.

`undeclared_requires` is set on 744 packages. Most are host modules (kong, resty, telescope: already tagged).
The rest are real: `bit` (88 rocks; Lua 5.4 has no `bit` library: it has native bitwise operators instead) and `socket` (41, plus
`socket.url` 24: rocks that need luasocket without saying so), `inspect`, `logger`.

Known gaps: only the latest version of each rock is indexed; no `luac` bytecode, no signatures.
