# Status

As of 2026-11-24. "Verified" means exercised by the offline test suite or by a real run against the public index.

## Works, verified

| area | state |
|---|---|
| Versions and resolver (LuaRocks semantics, one version per name, local/global rules) | unit tests; used for real installs |
| Transactional installer (staging, journal, hash-checked, safe to interrupt), records, `world`, `why`, `check --repair` | tests; real installs on Linux |
| Signed index client (ed25519 over every index file, sha256 over every file and source rock, blobs by hash) | tests; real downloads from the Pages index |
| Public index: 5261 packages, 1758 tagged for a host (Neovim, LOVE, ...), 536 rejected, `check-index` gate before every publish | live at `https://tibocub.github.io/vpm-index/index/v1`, the client default |
| Search and info with `--pure`, `--native`, `--host`, `--works`, `--here` | tests; real use |
| Pure Lua rocks | installed and loaded on vlr; about 1500 pure rocks recorded as loading cleanly (`vlr:ok`), the rest partial, failing or not yet tested |
| C rocks with the builtin build type | 352 rocks have a buildable plan; of those tested, 171 build and load on vlr in a sandbox |
| `make` and `cmake` rocks (plan recorded in the index, run in bubblewrap with no network) | 96 plans; 19 install and 15 load on vlr; the rest fail for the usual reasons (missing system libraries, unusual targets) |
| `vpm bundle` (C rocks compiled into the vlr binary) | tested on several rocks |
| `vpm publish` to luarocks.org (git remote + tag; dry run by default) | a test project was published and read back through the live site |
| Lock file (`vpm-lock.lua`) with per-package digest | tests |
| Defaults for desktops (public index and key, per-user directories) | tests |

## Not verified or not done

- No CI for this repository, and 42 local commits are unpushed. Tests are offline and run by hand: `VLR=../vlr/vlr sh tests/run.sh` (16 files, passing).
- Platforms: only Linux was used for the native builds. macOS (`-export_dynamic` link flags) and Windows with MSYS2 are untested. Windows has no dlopen in vlr, so only pure and bundled rocks apply there.
- Rocks without a hash-pinned source (rockspec-only uploads) cannot be installed. Versions other than the latest are not all hashed.
- Build types not supported: `command`, C++, Rust, Go. Rocks needing system libraries fail unless the library is present; the index records `no_plan_reason`.
- The rockspec `lua` version constraint is not enforced. Blob size cap is 512 KB.
- vpm itself is not published to luarocks.org (the name `vpm` is free) and has no self-update.
- On boards: pure rocks install file by file; there is no archive support, and the RP2040 was last exercised before the native-build and index changes.
- The signing key lives on one machine (`vpm-index-data`); there is no rotation or recovery procedure written down.
- No license file.
