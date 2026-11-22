# State on disk and tracking

## Scopes and roots

| scope | root | holds |
|---|---|---|
| global | `LIBDIR` = `/flash/lib/lua` (board), `/usr/lib/lua` (sim) | libraries and the files of installed programs |
| local | `<project or program dir>/lua_modules` | that program's private copies |

The runtime's `package.path` already searches local, then global
(vaporOS repo, `docs/lua-runtime.md`, "Module search path"). vpm does not change
how `require` finds modules; it only decides where files are placed. **No symlinks are used anywhere**
(littlefs on the board has none; recorded in the vaporOS compat-log).

## The database: many tiny files, never one big file

Loading one big database would cost RAM proportional to the number of packages. Instead each scope has a
directory `<root>/.vpm/` holding one small Lua-table file per installed package, loaded one at a time:

```
<root>/.vpm/
  pkg/<name>.lua       one record per installed package (version, kind, files, deps, uses, reason)
  world.lua            explicit set: name -> constraint the user asked for
  projects.lua         (global only) registered projects/programs outside the global tree
  lock                 present while vpm changes state (crash detection)
```

Record (local data is trusted, so plain Lua tables loaded with an empty environment):

```lua
return {
  name = "argparse", version = "0.7.1-1", kind = "lib",
  reason = "dep",                         -- "world" if the user asked for it
  files = { ["argparse.lua"] = "9f2c…" }, -- path -> hash (sha256, or crc32 on a first version)
  deps  = { penlight = ">= 1.10" },       -- constraints as declared
  resolved = { penlight = "1.13.1-1" },   -- versions it was resolved against, and where
  installed = "2026-10-27",
}
```

Transient data (reverse dependencies, "who uses X") is **computed by scanning `pkg/`**, not stored, so there is
no second copy to keep consistent. With dozens of small files this takes milliseconds and a few KB of heap if
done record by record.

## Programs and the question "who uses this library?"

A program is also a record (`kind = "app"`) with its own `resolved` table: for every package in its closure,
the version and the scope it was found in. A project (not installed system-wide) keeps the same thing in
`<project>/vpm-lock.lua`, committed by the user like a lock file.

`vpm why b` = scan global records and registered projects for any `resolved` containing `b`:

```
b 1.2.0 (global) is used by:
  argparse 0.7.1   (library, global)  needs b >= 1.0
  notes 0.3.1      (program, global)  resolved b 1.2.0
  ~/projects/foo   (project, registered) resolved b 1.2.0
```

Registered projects: the first `vpm i` run inside a project adds its path to the global `projects.lua`, so a
global update can see its impact. Unregistered code that merely `require`s a global library by hand is
invisible; vpm can only warn about what it knows (open question 5).

## Update impact

Before `vpm up -g b` applies anything it lists every package/program/project that (a) declares a constraint
the new version breaks, or (b) was resolved against the old version, and marks them *breaking* or *untested*.
The user chooses: update and re-resolve those, skip, or install the new version only locally for the project
that wants it.

## Unmanaged files

Files placed in `LIBDIR` by hand (the offline way) are not in any record. `vpm ls -g` shows them as
`(unmanaged)`; `vpm check` lists files no record owns. vpm never deletes or overwrites an unmanaged file
without confirmation, and `vpm adopt <name> <version> files…` can turn them into a record. A module name that
exists both as an unmanaged file and in the index is reported as a conflict, not overwritten.

## Safety and crashes

- Install is **stage, verify, then rename**: files are written under `<root>/.vpm/staging/<name>/`, hashes
  checked, then moved into place; the record is written last. A power cut mid-install leaves either the old
  state or a staging directory that `vpm check` can clean.
- The `lock` file marks an operation in progress. littlefs gives atomic file replacement per file but not
  across files; the stage-then-rename order is how consistency is kept.
- Uninstall removes exactly the files in the record, then the record, then empty directories.

## Flash wear and space

littlefs wears evenly but flash is only ~1 MB. vpm reports the size an install will take, refuses if less
than a configurable reserve would remain, and never keeps downloaded archives after install (streamed into the
staging directory, see [ram-budget.md](ram-budget.md)).

## The lock file (2026-11-22)
`vpm-lock.lua` in the project directory: `{ lockfile = 1, roots = { name = constraint }, packages = { name = { version, digest } } }`. `digest` is the sha256 of the sorted `dest sha256` lines of the
package's files as the index lists them.
- `vpm i` with no arguments: if a lock exists and its `roots` equal the `deps` of `vpm.lua`, it installs exactly the locked versions, asks nothing, and refuses (exit 4) when the index now serves different
  files for a locked version. If `vpm.lua` changed (roots differ) or there is no lock, it resolves again from `vpm.lua` and rewrites the lock.
- `vpm i NAME` adds what it installs to the lock; `vpm rm NAME` drops it unless `vpm.lua` itself lists it (then the next `vpm i` brings it back).
- A damaged lock is an error (delete it to start over); the old format (versions only) is ignored and replaced.
- Only the local (project) scope has a lock. Packages from a local directory (`vpm i ./dir`) have no digest.
No `--locked` flag: the lock is simply followed when it is valid (decided with the user, 2026-11-22).
