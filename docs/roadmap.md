# Roadmap

## Immediate
1. Push both repositories; add CI for vpm (offline tests on Linux with a built vlr; a macOS job).
2. Pick a license; publish vpm itself to luarocks.org and make `vpm` installable by `vpm`.
3. A one-line install path: a release of vlr with vpm bundled or a script that fetches both.
4. macOS and Windows (MSYS2) rounds for native builds and fix what they find.
5. Refresh the index regularly (a documented procedure or a scheduled job), including `works with vlr` results; write down key rotation and backup.
6. Raise the number of C and make/cmake rocks that build: read the failure categories in the compat run and fix the common ones (missing `external_dependencies`, platform tables).
7. Enforce the rockspec `lua` constraint; hash older versions on demand.

## Next
- `command` build type under the same sandbox; C++ rocks (compiler detection); rocks without a pinned source (fetch from git at a tag, record the hash).
- Pre-built binaries per platform (ABI tag `engine-dialect-platform`) so a machine without a compiler can install C rocks; signed like the rest of the index.
- Archive extraction on boards (or a streamed format) so large rocks install without per-file requests.
- Mirrors without TLS for devices that cannot do it: the same signed files served over plain HTTP or an SD card.
- Better `outdated`, `clean`, and a `vpm run` for installed programs.
- Network-time and size budgets on the RP2040 re-measured with current code.

## Long-term goals
- vlr + vpm as a credible alternative to Python + pip and Node + npm for portable programs: a user installs one binary and gets most of luarocks.org that can work, with honest compatibility information for each package.
- The same tool on desktop, browser (WASM) and microcontroller.
- Our index stays a thin, signed mirror and compatibility oracle; luarocks.org stays the source of packages. The tools stay usable by anyone who wants to run their own index.

## Research and ideas
- Versioned store (several versions of one library side by side) with per-program search paths; the records are already keyed by name and version.
- Namespaced `require` per package to lift the one-version-per-process rule (costs RAM; not proposed).
- A continuously running compatibility service: new rock versions loaded on vlr automatically, results reflected in search.
- Reproducible builds and attestation for source-built rocks.
- Using vpm as the package manager for other vaporOS interpreted languages (shell programs).
