# Design overview

> Historical: written when vpm was a vaporOS-only, pure-Lua-only tool. vpm is now a general package manager that also builds C rocks; see [status.md](status.md) and [spec.md](spec.md) for the current state. Kept for the reasoning.

## Vocabulary

| term                         | meaning                                                                                                           |
|------------------------------|-------------------------------------------------------------------------------------------------------------------|
| **package**                  | a named, versioned set of files, Lua modules and/or commands                                                      |
| **library** (`kind = "lib"`) | a package other code `require`s                                                                                   |
| **program** (`kind = "app"`) | a package with commands (`bin`) the user runs; has its own dependencies                                           |
| **project**                  | a directory the user works in, with a `vpm.lua` manifest, not installed as a package                              |
| **scope**                    | where a package is installed: **global** (system-wide) or **local** (a program's or project's `lua_modules/`)     |
| **provided**                 | a library built into the firmware (lfs, lpeg, cjson); satisfies dependencies, is never downloaded                 |
| **world**                    | the packages the user explicitly asked to install (portage's term); everything else was pulled in as a dependency |
| **index**                    | the small metadata service vpm reads; derived from LuaRocks, see [index-and-network.md](index-and-network.md)     |

Global root on a board is `/flash/lib/lua`, on the sim `/usr/lib/lua` (`CONFIG_VAPOROS_VLUA_LIBDIR`). Files
copied there by hand are legitimate: vpm treats them as *unmanaged* packages (see
[state-and-tracking.md](state-and-tracking.md)).

## Commands (npm-shaped, first draft)

```
vpm i [pkg[@range]...]    install; with no argument, install what ./vpm.lua asks for
vpm i -g pkg              install system-wide (libraries, or a program with its commands)
vpm rm pkg                remove (refuses if something still uses it, unless --force)
vpm ls [-g]               what is installed here / system-wide
vpm why pkg               which programs and packages use it (reverse dependencies)
vpm up [pkg]              update; prints what each update would affect first
vpm outdated              installed packages that have newer versions
vpm search words          search the index
vpm info pkg              versions, dependencies, kind, why it is or is not installable
vpm world                 the explicit set (portage's @world)
vpm clean                 remove dependency-only packages nothing uses any more (portage's --depclean)
vpm check                 verify files against recorded hashes, find unmanaged files
```

Everything that changes state supports `--dry-run` and prints the plan first (what is downloaded, where it goes
(global/local), what is reused, what is shadowed, which programs are affected). The plan output is a design
feature, not decoration: it is how the user sees a conflict before it bites.

Flags in the npm spirit: `-g` global, `--deps=global|local|auto` where new dependencies of a local install
go (open question 1), `-n` dry run.

## Two layers, one tool

```
 vpm  (one program, Lua)
  ├── resolver        pure logic: versions, constraints, global/local placement
  ├── state           reads/writes the on-disk records
  ├── index client    asks the index about a package, downloads files
  └── installer       places files, writes records, creates command launchers
```

The resolver does not do I/O. It is given the installed state, the provided set and an `index(name)` function,
and returns a plan. That makes it testable on a normal PC and on the sim without a network, with a fake index.

## Programs

A program package declares commands:

```lua
return { name = "notes", version = "0.3.1", kind = "app", lang = "lua",
         bin = { notes = "notes.lua" }, deps = { lpeg = ">=1.0", penlight = "~> 1.13" } }
```

`vpm i -g notes` installs the files, resolves dependencies with the global-first policy, and makes `notes`
runnable from any directory. How commands become runnable is a vaporOS question (shebang support and a
`PATH` directory), see [vaporos-prerequisites.md](vaporos-prerequisites.md). Shell programs (`lang = "sh"`) fit
the same shape; shell libraries are out of scope for now.

## Source-based, in the portage sense

Portage fetches sources and builds locally. For pure Lua "build" is small, but the idea still applies and is
useful: vpm installs *from the source tree of the package*, not from a prebuilt binary, and install steps are
the place for local decisions:

- strip and precompile to bytecode (`luac -s`) when the user wants less RAM/flash and the Lua build matches,
- drop tests/docs from the installed copy,
- later: per-package options ("USE flags") if a real need appears. Not now.

## What vpm deliberately copies from LuaRocks

Version syntax and comparison (`1.2.3-1`, `~> 1.2`, `>= 1.0, < 2`), the rockspec as the source of truth for
dependencies and build description, and the LuaRocks repository as the package source. What we do **not** copy:
the global mutable `rocks_trees`, C building, and the per-rock folder layout (`lib/luarocks/rocks-5.4/...`),
which wastes flash and directory entries on a small filesystem.
