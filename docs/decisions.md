# Decision log

Dates are absolute. A decision here overrides any proposal in the other documents.

## 2026-10-27 — user decisions at the start of the project

- The project is its own repository, `vpm`, like vaporshell. Name is a placeholder.
- vpm runs **on the device** (no PC dependency for users). Boards without networking get libraries copied by
  hand into `/usr/lib/lua` or `/flash/lib/lua`.
- **One tool** for both libraries and whole programs (language-level + system-level package management), for
  interpreted code only (Lua, shell). Compiled programs are handled at firmware build time.
- Command line modelled on npm (`i`, `-g`); system-package model on portage (world, source-based).
- Reuse LuaRocks data and conventions; **filter to pure Lua** so native rocks are never offered.
- Share libraries between programs to save RAM/flash; allow global installs of dependencies; detect version
  conflicts; track which program uses which library; allow mixing global and local resolution.
- The RP2040 is the smallest officially supported target: the basics must run there; extra features may be
  missing there.
- The simulator keeps **its own** library folder and stays close to a physical board (host files accessible,
  vaporOS files stay inside vaporOS). It does not reuse the host's luarocks tree.
- Shebang support for Lua scripts in vaporshell is wanted.
- Networking is tested on the sim until a networked board (Pico W, ESP32) is available.

## 2026-10-27 — design proposals made by Claude, awaiting the user

See [open-questions.md](open-questions.md). Notably: derived index (Q3), `--deps=auto` (Q1), closure rule for
shadowing (dependency-resolution.md).

## 2026-10-27 (later)

- Q1: accepted: reuse what is installed, `--deps=auto` (global unless it conflicts), plan printed first.
- Q2: delegated to Claude; chosen: flat global tree first, records and resolver keyed by (name, version) so a
  versioned store can be added later. Reason: littlefs has no symlinks, a store needs a per-program path
  assembled at start, and the conflict cases it removes can already be handled by local copies.
- Q3: accepted: the **pure-Lua filter and the index builder are the first code**, not a later feature.
- Prerequisite P1 (shebangs in vaporshell) done.
- First code written: LuaRocks-compatible versions (`~>` is a prefix match, verified against luarocks) and the
  filter. Result and findings in pure-lua-filter.md; rule 11 (host-application rocks) added because of it.
- Host-application rocks (Neovim, OpenResty, LÖVE) are **tagged, not rejected** (user, 2026-10-27): users are not
  expected to install them by mistake, the tag is for search/info. Pure-Lua rules stay hard rejections.
- `compat53` is a no-op on Lua >= 5.3, so it is a provided stub (the runtime must preload an empty module).
- Rule 8 corrected: check what a rock *installs*, not everything in its repository.
- Source stage and `index/v1` emission implemented; first full run: 1,939 packages.

## 2026-10-27 (spec)

- vpm is written in **Lua**, with C only for firmware primitives where they matter (sha256 first; maybe the
  HTTP/TLS client). Measured on the RP2040: compiling vpm-sized source costs 0.54 s and 58 KB of heap, stripped
  bytecode loads in 0.01 s with 33 KB, so ship bytecode; pure-Lua sha256 is 7 KB/s, so hashing must be C.
  vpm should relax the early-GC setting for itself (resolver code is 3.7x slower under `pause 100`).
- Write the specification before the device client: [spec.md](spec.md). Its PROPOSED items are open.
- Accepted: appdir + launcher (validate in daily use on real boards), register projects by default, `name@1.2`
  = LuaRocks prefix match (equals "1.2.x"), prompt rule extended: ask whenever dependencies beyond the named
  packages must be fetched (apt-style summary with sizes).
- `vpm init` is in v1. `vpm publish` and git are open (Q11, Q12) and do not block each other.
- Resolver implemented (`lib/vpm/resolver.lua`, `tests/test_resolver.lua`). Details settled while testing:
  rule 1 (global needs global) binds only packages being newly installed globally, a reused global package may be
  served by a local shadow; in `auto` mode every new global candidate has a local fallback; `scm`/`dev` versions
  only when a constraint names one; error messages prefer the specific cause (deepest) over "no combination".
- Command naming (user): long explicit canonical names, short forms are aliases only where intuitive.
- State layer (`state.lua`, `fs.lua`), `file://` transport, index client and installer written and tested
  (`tests/test_install.lua`: stage/verify/rename, unmanaged files, path escapes from a hostile index, locks,
  hash failures, programs with launchers, local scope). First on-board measurements in ram-budget.md.
- Journal approach adopted (user, 2026-10-27): fresh installs are written in place with the lock file as journal,
  upgrades keep staging, new records are written directly; `installer:repair` undoes a crashed run. Install of the
  7-package test went from 28.6 s to 13.2 s on the RP2040. Cost: after a crash, a fresh package's partial files
  exist until `repair` runs (vpm refuses to start another run until then).
- CLI written (`cli.lua`, `plan.lua`, `cmd/*.lua`): one module per command, loaded on demand; the context builds
  index, installer and maintainer lazily; the resolver is unloaded before downloading. Install code split from
  maintenance code (`maintain.lua`). Verified on the RP2040 (bytecode, searcher over /flash/vpm_*.luac).
- Not done in the CLI: `vpm install ./dir` (local sources), `search`, `outdated`, `clean`, `adopt`, `--no-register`
  is parsed but only controls registration, impact analysis against registered projects on `upgrade -g`.

