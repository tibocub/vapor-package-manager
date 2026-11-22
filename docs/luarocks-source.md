# luarocks.org as the source, our index as a signed hash mirror (design, 2026-11-22)

Decision (user): consume luarocks.org directly; our index only mirrors **hashes and dates for every rock**, signed, so a download over plain HTTP (no TLS, as on a small board) can still be verified.
It also carries what only we compute: native class, host tag, "works with vlr" result.

## What luarocks.org gives us (checked 2026-11-22)
- `manifest-5.4` (Lua table), `manifest-5.4.zip`, `manifest.json`: every rock and version. No hashes, no dates in the manifest.
- `NAME-VERSION.rockspec` and `NAME-VERSION.src.rock` (zip: rockspec + source) for each version, served with `Last-Modified` and an `ETag` (an MD5: not a security hash).
- Upload: `POST /api/1/bearer/upload` (see decisions.md). Rockspecs point at upstream sources (git, archives); about 17% of upstreams in a random sample were dead (16 download failures,
  14 missing tags, 10 `git://`/ssh URLs of 239), the `.src.rock` copy is the fallback.

## What the mirror records per version (index entry `luarocks` field)
`rockspec = { sha256, size }`, `src = { sha256, size }` (the `.src.rock`), `date` (Last-Modified of the rockspec, ISO), plus what the builder derived (deps, native, host, files for pure rocks).
vpm checks every download against these. Because the signature covers the entry, the transport does not need to be trusted.

## Two ways to install, same index
1. **Files** (pure rocks, boards): the entry lists every file with sha256 and a URL (upstream raw URL when stable, else a blob next to the index): no archive extraction needed. Works today.
2. **Source rock** (native rocks, desktop): download `.src.rock` (or the upstream source), verify against `src.sha256`, extract, build. Needs unzip support in vpm (system `unzip` or a vlr module) and the build step (later).

## Open points for the user
- Should vpm also work without our index (reading luarocks.org's manifest and rockspecs itself, trusting TLS)? It is a big download for a board (the 5.4 manifest is several MB) but fine on a desktop.
  Proposal: yes on desktop as a fallback (`index = "luarocks"`), never on boards.
- The "works with vlr" result is produced by our crawler on one machine; it needs a stated method and date in the entry (so a stale or wrong result can be seen and disputed).
