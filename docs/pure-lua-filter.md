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
| 8 | the source archive, once fetched, contains no `.c`, `.cpp`, `.h`, `.so`, `.dll` outside `doc/`, `test/`, `examples/` | catches `builtin` rocks whose `modules` omit native code, and `none` rocks that ship binaries |
| 9 | the rock does not reference `ffi`, `jit.` (LuaJIT-only) in its modules | cheap grep; LuaJIT-only code cannot run on PUC Lua |
| 10 | the source is fetchable without a build step (git tag, tarball or zip with a stable URL) | needed to compute hashes |

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
