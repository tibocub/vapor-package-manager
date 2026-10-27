# Open questions

Ordered by how much they block design. Mark each with a decision in [decisions.md](decisions.md) when settled.

## Q1. Where do new dependencies of a local install go by default?
Options: `local` (npm-like, simple, duplicates), `global` (shares, but changes the system from a project
command), `auto` (global unless it conflicts; reuse always wins). Proposal: `auto`, with the plan printed.
Needs the user's call because it changes the system from a command that looks project-local.

## Q2. Flat global tree (one version per name) or a versioned store?
Flat is what we have: simple, current `package.path` unchanged. A versioned store (`<name>/<version>/`) lets
two versions coexist globally (portage "slots", Nix-like) and removes most conflict cases, but needs a
per-program path assembled at start (reading a lock file) because there are no symlinks. Proposal: flat first,
keep the record format ready for a store. **Decision (Claude, delegated by the user 2026-10-27): start flat,
but design every record and the resolver around (name, version) so a store is an addition, not a rewrite.**

## Q3. Is a derived, published index acceptable?
Needed because the device cannot evaluate rockspecs or hold the manifest. The cost is that someone runs the
index builder and hosts static files. Packages still come from their upstream sources. Alternative: none
that works on 187 KB.

## Q4. What exactly is a "program"? Where do its private libraries live?
A program may be installed globally and share libraries globally, or keep `lua_modules` inside its own
directory. Proposal: shared by default (the RAM goal), private only on conflict. Where do program files live
(`<root>/apps/<name>/`)? Do programs get a per-program data directory?

## Q5. Tracking projects outside the global tree
`vpm i` in a project registers it, so a global update can warn. Unregistered code that `require`s globals is
invisible. Acceptable? Should registration be opt-out?

## Q6. Namespaced requires (each package sees its own dependency versions)
Would remove the one-version-per-process rule. Costs RAM and diverges from how Lua works. Currently no.

## Q7. Signing
Who holds the index signing key, how is it rotated, what happens when the key is lost. Not needed to start;
needed before anything public.

## Q8. Mirrors for upstream files
If a rock's upstream URL disappears, the index entry breaks. Do we mirror files (then we do host packages) or
accept breakage and report it?

## Q9. Name
"vpm" is a placeholder. Check for clashes with existing tools before it sticks.

## Q10. Per-board capability profile
Which commands and options does the RP2040 build include (`search`, bytecode) versus a PC or ESP32 build?
Declarative per-board config, like the rest of vaporOS?

## Research items
- **R1** HTTPS/TLS handshake RAM and time on a Pico W (mbedTLS, CA bundle size). Hardware not available yet.
- **R2** Which NuttX simulator networking mode reaches the host network (TAP vs usrsock) and what it needs.
- **R3** Real numbers: how many LuaRocks rocks are accepted by the pure-Lua filter, and how many dependency
  closures are small. Run the filter on the real manifest as the first piece of code (it is a PC script).
- **R4** Does `string.dump(f, true)` plus loading it on the board work with our 64-bit build, and how much RAM
  does it save compared with compiling source on the device?
