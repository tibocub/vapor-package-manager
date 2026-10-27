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

## Q11. Publishing: what does `vpm publish` do, and where does it send?
Packages are not hosted by us (non-goal); the index points at upstream sources. So publishing = **submitting a
small manifest** (name, version, source URL + tag, kind) to the program registry, whose index builder fetches,
checks and hashes it exactly like a LuaRocks rock. Submission needs a transport: an HTTPS API endpoint, the
GitHub REST API (opens a pull request with only HTTPS + JSON, no git client), or a file the author submits by
hand. `vpm init` and a local `vpm check-manifest` are needed first and need none of this. Realistically publishing
happens from a PC first; on a board it needs TLS (R1) and a credential on the device.

## Q12. A git for vaporOS (separate project, not a vpm dependency)
Wanted for its own sake. A subset (clone/fetch over smart-HTTP, checkout, status, log, add, commit, push) is
feasible; full git is not. Needs zlib inflate/deflate, sha1, pack and delta parsing, the index format and the
HTTP(S) client. Memory is the limit: delta resolution and large packs do not fit in 187 KB, so it is a
"small repositories" tool on the RP2040. See the discussion in the chat of 2026-10-27; own repo when started.

## Research items
- **R1** HTTPS/TLS handshake RAM and time on a Pico W (mbedTLS, CA bundle size). Hardware not available yet.
- **R2** Which NuttX simulator networking mode reaches the host network (TAP vs usrsock) and what it needs.
- **R3** (answered 2026-10-27, see pure-lua-filter.md): 1,663 of 4,929 rocks (33.7%) pass, upper bound. Still
  open: size of typical dependency closures and the effect of rules 8-9.
- **R4** Does `string.dump(f, true)` plus loading it on the board work with our 64-bit build, and how much RAM
  does it save compared with compiling source on the device?
