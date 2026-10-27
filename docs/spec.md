# vpm specification (v1 draft)

What vpm does, precisely. Concepts live in [design.md](design.md), resolver rules in
[dependency-resolution.md](dependency-resolution.md), disk layout in [state-and-tracking.md](state-and-tracking.md).
Items marked **PROPOSED** are Claude's defaults awaiting the user's decision; everything else restates a decision
from [decisions.md](decisions.md).

## Principles

1. **Plan first.** Every command that changes state computes a plan, prints it, then applies it. `-n` stops after
   the plan. Nothing is downloaded before the plan is accepted except small index metadata.
2. **Never surprise the system from a local command.** A local install may add global packages only under
   `--deps=auto|global` and the plan says so on its first line.
3. **Never change or delete what vpm did not install** (unmanaged files) without explicit confirmation.
4. **Safe to interrupt.** Stage, verify, rename; the record is written last (state-and-tracking.md).
5. **Everything runs offline** from a `file://` mirror; the network is one transport among others.
6. Written in Lua; C only for primitives (sha256 and later maybe an HTTP/TLS client) exposed by the firmware.
   (Decision 2026-10-27, user.)

## Vocabulary additions

| term | meaning |
|---|---|
| **root** | one scope's directory tree: the global root, or a project/program's `lua_modules` |
| **manifest** | `vpm.lua` in a project: what it wants |
| **lock** | `vpm-lock.lua` in a project: what it resolved to (committed by the user) |
| **plan** | the list of actions the resolver produced |

## Paths and configuration (PROPOSED)

One small file, `vpm-config.lua` (board: `/flash/etc/vpm.lua`, sim: `/etc/vpm.lua`), generated at firmware build
time from the board's declarative config, overridable by `--root` etc. for tests:

```lua
return {
  libdir = "/flash/lib/lua",     -- global libraries (== CONFIG_VAPOROS_VLUA_LIBDIR)
  appdir = "/flash/apps",        -- one directory per installed program
  bindir = "/flash/bin",         -- launchers; on PATH
  index  = "https://…/index/v1", -- or file:///sd/mirror/index/v1
  reserve = 64 * 1024,           -- never leave less free flash than this
  profile = "small",             -- "small" (RP2040) | "full": enables search, outdated, clean…
}
```

A **program** is a package with `kind = "app"` (it declares `bin`):

```
<appdir>/<name>/           the program's own files, exactly as listed in its record
<appdir>/<name>/lua_modules/   its private libraries, only when it needed local ones
<bindir>/<command>         launcher: a 3-line Lua script with a shebang
```

Libraries a program needs are global by default (shared, the RAM goal); `lua_modules` appears only on conflict or
`--deps=local`. The launcher puts the program's directory on `package.path` before running its entry file, so
program-private modules are found first, and does not touch the global search path:

```lua
#!/bin/lua
package.path = "/flash/apps/notes/lua_modules/?.lua;/flash/apps/notes/?.lua;" .. package.path
arg[0] = "/flash/apps/notes/notes.lua"; return dofile(arg[0])
```

No symlinks anywhere (littlefs); launchers are the symlink substitute.

## Names and versions on the command line

```
notes              any version the resolver likes (highest compatible)
notes@1          every 1.x            (LuaRocks "~> 1")
notes@1.2          1.2 and 1.2.x, not 1.3  (LuaRocks "~> 1.2"; npm users would write 1.2.x: same meaning)
notes@1.2.3-1      exactly that version
notes@">=1.0,<2"   a full constraint (starts with an operator); quote it for the shell
./dir  file:///sd/x.rock-dir   a local source (see "Local sources")
```

## Commands

**Naming rule (user decision 2026-10-27):** every command has a long, explicit canonical name; short forms are
plain aliases of it, only where they are intuitive (`i`, `rm`, `ls`, `u`); the others (`why`, `info`, `check`,
`world`, `search`, `outdated`, `clean`, `adopt`, `init`) have none. Help, docs and error messages use the long name.

Global options: `-g` global scope, `-n/--dry-run`, `-y/--yes` (no prompt), `--deps=auto|global|local`
(default `auto`), `--index URL`, `--root DIR` (scope root, for tests), `-q`, `-v`.
Exit codes: **0** success, **1** error, **2** usage, **3** unresolvable (conflict; message names the chain),
**4** network or integrity failure (nothing was changed).

Prompting (user decision 2026-10-27): a plan that only installs **the packages the user named** is applied without
asking (`vpm install -g ansicolors` with no dependencies). Anything else asks, apt/dnf style, unless `-y`: extra
dependencies to fetch, removals, replacements, shadowing, or the global scope touched from a local command. The
prompt lists everything and the total download and installed size:
```
The following packages will be installed:
  notes 0.3.1-1 (global)   penlight 1.14.0-1 (global)   lua-term 0.8-1 (global)
Download: 58 KB   Installed: 96 KB   Free flash after: 612 KB
Continue? [Y/n]
```
Without a terminal and without `-y` it refuses.

| command | does | scope default |
|---|---|---|
| `vpm init` | create a `vpm.lua` in the current directory (asks name, kind, entry file; `-y` takes defaults); no network | local |
| `vpm install [spec...]` (alias `i`) | install the specs; no spec = what `./vpm.lua` asks for (updates `vpm-lock.lua`) | local |
| `vpm install -g spec...` | install system-wide: a library, or a program with launchers | global |
| `vpm remove spec...` (alias `rm`) | remove the named packages; refuses if another record needs one (`--force` overrides, plan lists the breakage) | as `install` |
| `vpm list [-g]` (alias `ls`) | list installed packages: name, version, kind, `world`/`dep`, scope; unmanaged files at the end | local |
| `vpm why NAME` | everything that uses NAME (records + registered projects), with the constraint each one declares | both |
| `vpm upgrade [spec]` (alias `u`) | update to the highest version the constraints allow; shows impact first | as `install` |
| `vpm info NAME` | versions, kind, dependencies, size, origin, host-tag, and why a missing package is not installable | – |
| `vpm check` | verify installed files against recorded sha256; list unmanaged files, orphaned staging dirs, stale locks | both |
| `vpm world` | the explicit set | both |
| `vpm search WORDS` | search the index (profile `full`) | – |
| `vpm outdated` | installed packages with newer versions (`full`) | – |
| `vpm clean` | remove dependency-only packages nothing uses (`full`; on `small` it is `rm` of what `ls` shows as unused) | both |
| `vpm adopt NAME VER FILE...` | turn unmanaged files into a record (`full`) | global |

**Required on the RP2040 (`small`):** `init`, `install`, `remove`, `list`, `why`, `upgrade`, `info`, `check`, `world`.

### `vpm install` in detail

1. Read config and records of the target scope(s). Load the provided-library table from the firmware.
2. Resolve (dependency-resolution.md). Metadata is fetched per package, one small file at a time.
3. Print the plan:
   ```
   install  penlight 1.14.0-1   local   9 files  41 KB   (shadows global 1.13.0-1)
   install  lua-term 0.8-1      global  1 file    5 KB
   reuse    argparse 0.7.2-1    global
   reuse    lpeg 1.1.0          firmware
   free flash after: 612 KB      programs affected: none
   ```
4. Download each file to `<root>/.vpm/staging/<pkg>/`, hashing while writing; refuse a size or hash mismatch.
5. Move files into place, write records, update `world.lua` (explicitly named packages get `reason = "world"`;
   a package already installed as a dependency is promoted, never reinstalled), register the project (see
   below), write launchers for programs.
6. Remove staging. On any failure before step 5 the system is unchanged.

Naming a package that is already installed at a fitting version is a no-op that only updates `world`.
A package tagged `host` (Neovim/OpenResty/LÖVE) installs normally; the plan prints `note: written for neovim`.

### Local sources (implemented)

`vpm install ./dir` and `file://` mirrors install without the network. A directory with a `vpm.lua` that has `name` and
`version` is installed as that package; its dependencies are resolved from the index like any other. This is how
a program author tests an install, and how an SD-card mirror works. Without a `files` list in the manifest every
`.lua` file is installed except `vpm.lua`, `vpm-lock.lua`, `lua_modules/`, `tests/`, `test/`, `spec/` and dot
directories. A local source is always reinstalled (never "reused"), so edit-and-reinstall works; the record keeps
the directory as its `origin`.

### `vpm.lua` (manifest) and `vpm-lock.lua`

```lua
return {
  name = "mytool", version = "0.1.0",           -- optional for a plain project
  kind = "app", bin = { mytool = "main.lua" },  -- optional: makes the directory installable as a program
  deps = { penlight = "~> 1.13", lpeg = ">= 1.0" },
}
```

The lock records the resolved version and scope of every package in the closure and is only rewritten by
`vpm install` / `vpm upgrade`. Plain Lua tables, loaded with an empty environment. Index data is JSON because it is
remote and is never executed.

### `vpm upgrade`

`vpm upgrade` (no argument) = every package in `world` of the scope. For a global package the plan first lists
**impact**: records and registered projects whose declared constraint the new version breaks (`breaking`), or that
were resolved against the old version (`untested`). Choices: apply, skip that package, or install the new
version locally for the project that asked. Global updates never run silently from a local command.

### Projects (PROPOSED)

The first `vpm install` in a directory registers it in the global `projects.lua` so `why` and `upgrade -g` can see it.
Registration is the default and `--no-register` opts out; unregistered use of global libraries is invisible, and
`vpm check` says so. Moving a project makes a stale entry; `check` prunes missing paths.

## Failure behaviour

- Unsatisfiable: exit 3, message *"notes needs lpeg >= 1.1 (from notes); penlight 1.13 needs lpeg < 1.0 (from
  penlight): no version satisfies both"*.
- Package not in the index: `info` answers why (rejected: native code / host app / source unavailable) when the
  index carries a reason; otherwise "not found".
- Hash mismatch, short download, no space left (reserve): exit 4, staging removed, nothing changed.
- Stale `lock` file (power cut): the next command says so and offers `vpm check --repair`.

## Not in v1

Optional dependencies, per-package build options ("USE flags"), a versioned store (slots), namespaced requires,
`vpm publish` and any git support (Q11, Q12),
signature verification (the format leaves room, Q7), bytecode install (R4 first), `shell` libraries, installing
older versions that the filter did not index, publishing.

## Open points (see open-questions.md)

Q4 is answered above (accepted 2026-10-27, to be validated by daily use on real boards: apps in `appdir`, shared
libs by default, private libs only on conflict), Q5 (accepted: register by default), Q10 (PROPOSED: `profile` in the config file). Q7, Q8, Q9 remain open.
