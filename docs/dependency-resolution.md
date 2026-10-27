# Dependency resolution

## The one fact that shapes everything

**A running Lua program has exactly one version of each module name.** `require "b"` returns the same table
to everybody in the process. Two libraries that need incompatible versions of `b` cannot both work in one
process the way npm's nested `node_modules` allows. So the resolver must pick *one version per package name
per program*, and a plan is only valid if every package in the program's closure accepts that one version.

(Alternative that lifts this: namespaced module loading, i.e. each package gets its own `require` that looks
in its own dependency directory. It is possible in Lua but changes how code behaves and costs RAM. Not
proposed; recorded in [open-questions.md](open-questions.md).)

## Versions

LuaRocks-compatible, so the data from rockspecs needs no translation:

- version = dotted number groups plus an optional `-revision` (`1.13.1-1`), plus `scm`/`dev` for unreleased,
- constraints: `==`, `~=`, `<`, `<=`, `>`, `>=`, `~>` (pessimistic: `~> 1.2` is `>=1.2, <2`; `~> 1.2.3` is
  `>=1.2.3, <1.3`), comma separated meaning AND,
- comparison on the numeric groups, then revision. `scm` sorts last and is never chosen unless asked for.

## Inputs to the resolver

1. Requirements: from the command line and/or `vpm.lua` (name -> constraint).
2. **Provided** libraries (firmware), with versions, mapped to rock names (`luafilesystem` -> `lfs`,
   `lua-cjson` -> `cjson`, `lpeg`). A provided library satisfies a dependency if its version fits, and is
   never replaced by a downloaded one (a downloaded Lua copy of lpeg would not even work).
3. **Installed**: global records and the local records of the target project.
4. **Index**: `index(name)` returns the known versions with their dependencies (only on demand).
5. Policy: the scope the user asked for, and `--deps`.

## Candidate order for a name (the "prefer what we already have" rule)

For each required name, candidates that satisfy the merged constraint are tried in this order:

1. provided by the firmware,
2. already installed in the local tree,
3. already installed globally,
4. from the index, highest version first.

The first three cost nothing to install, which is the RAM/flash goal. A candidate from the index is chosen
only if nothing already present satisfies the constraints.

## Algorithm (backtracking, deliberately simple)

The Lua ecosystem has small dependency graphs (typically fewer than 10 packages), so a full SAT solver such as
PubGrub is not worth its code and RAM.

```
resolve(pending, chosen):
    if pending is empty: return chosen
    take name N with its accumulated constraint C (the AND of every requirement seen so far)
    for each candidate v of N that satisfies C, in the order above:
        if the closure rule (below) fails for v: continue
        chosen' = chosen + {N: v};  pending' = rest + v's dependencies
        result = resolve(pending', chosen')
        if result: return result
    fail: report N, C and who contributed each constraint
```

Metadata for a package is fetched the first time the resolver needs it and cached for the run, so a failed
branch never re-downloads. Only metadata (small) is fetched during resolution; file downloads happen after a
plan is accepted.

A failure message must name the chain: *"notes needs lpeg >= 1.1 (from notes), penlight 1.13 needs lpeg < 1.0
(from penlight): no version satisfies both"*.

## Global versus local placement

Rule set (this is where the design differs from npm):

1. **A global package may depend only on global (or provided) packages.** A system-wide library must not need
   something that only exists inside one program's directory.
2. **A local installation may use global and provided packages freely**, which is how one physical copy serves
   several programs.
3. **Placement of a package that must be newly installed** follows the policy:
   - `-g` install: everything new goes global (rule 1 forces it),
   - local install, `--deps=local` (npm-like): new packages go in the project's `lua_modules`,
   - local install, `--deps=global`: new packages go global, to share them,
   - `--deps=auto` (candidate default): new packages go global *if nothing installed already uses a
     conflicting version of them*, else local.
4. **A conflict is never resolved by silently changing a global package.** Changing a version someone else uses
   needs an explicit `vpm up -g` with the impact list.
5. **Shadowing and the closure rule.** If the project needs `b 2.x` but the system has `b 1.x`, `b 2.x` is
   installed locally and shadows the global one (the project's `lua_modules` come first on the search path).
   The shadow applies to the *whole process*, so any global package in the program's closure that depends on
   `b` now gets `b 2.x`. The resolver therefore checks every global package that (transitively) requires `b`:
   - if it accepts `b 2.x`, fine, the shadow is safe,
   - if it does not, that package is installed **locally too** (a private copy), and the check repeats for its
     own dependencies, until the closure is consistent or it fails.

   This is the case the simple "put the one conflicting library in the program's directory" idea runs into:
   the library you shadow may be used by other libraries you got from the global tree.

## Worked example

System has (global): `penlight 1.13`, `argparse 0.7` (needs `penlight >= 1.10`), firmware provides `lpeg 1.1`.

`vpm i` in a project whose `vpm.lua` wants `lpeg >= 1.0`, `argparse ~> 0.7`, `penlight >= 1.14`, `lua-term`:

1. `lpeg`: provided 1.1 satisfies. Nothing to do.
2. `argparse`: global 0.7 satisfies. Reuse.
3. `penlight >= 1.14`: global 1.13 does not satisfy; index has 1.14. Candidate: install `penlight 1.14` locally.
4. Closure check: `argparse` (global) depends on `penlight >= 1.10`, 1.14 satisfies it, so shadowing is safe.
5. `lua-term`: not installed; new package, `--deps=auto` puts it global unless it conflicts; it does not.

Plan shown to the user: *download penlight 1.14 (local), lua-term 0.8 (global); reuse argparse 0.7 (global),
lpeg 1.1 (firmware). Programs affected by the global change: none (new package). Shadowed: penlight 1.13
(global) by 1.14 in this project; global users of penlight in this project's closure: argparse (compatible).*

If `argparse` had said `penlight < 1.14`, the plan would instead be: install a local copy of `argparse` (and
anything else that rejects 1.14) and warn how much that duplicates.

## Updating a global package

`vpm up -g b` computes, for the target version, every installed program/package whose recorded constraints
reject it, or that was resolved against the old version without a constraint that pins it. The report lists
them; the user can accept (those programs are re-resolved), skip the update, or keep the old global version
and give the new one only to the project that asked. See [state-and-tracking.md](state-and-tracking.md).

## Cycles, optional dependencies, platform markers

- Cycles: rare in Lua; report as an error, name the cycle.
- Optional dependencies: not supported at first (rockspecs have none).
- Platform-specific dependencies in rockspecs (`platforms`): evaluate for vaporOS; a rock whose result
  depends on `unix`/`windows` only is filtered by [pure-lua-filter.md](pure-lua-filter.md).
