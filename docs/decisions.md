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
