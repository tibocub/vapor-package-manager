# Signed index (implemented 2026-10-27)

Goal: an index fetched over plain `http://` (or from an SD card, a USB bridge, any untrusted mirror) can be trusted,
so small boards need neither TLS nor a CA bundle. The model is apt's: **signature over metadata, hash over content**.

## What is signed, by whom

- The publisher (us, or anyone running `index-builder`) holds an **ed25519 private key**. The public key (32 bytes,
  64 hex characters) goes in the device's vpm config: `keys = { "1682b6…" }`. Several keys may be listed (rotation:
  add the new one, publish with it, drop the old one later).
- Every index file `F` (`meta.json` and each `p/xx/NAME.json`) has a sibling `F.sig` of 64 raw bytes: the ed25519
  signature of the file's exact bytes. `lua index-builder/sign.lua sign KEY.pem index/v1` writes them (openssl;
  1,930 files in about 15 s).
- Each package file lists the sha256 of every file it installs; the installer checks them as before. So the signature
  covers the hashes, and the hashes cover the content. **File bodies need no signature and no trusted server**, they
  can come from any mirror, upstream GitHub or a content-addressed store.
- Signing a rock-derived entry means "these are the hashes we saw when we built the index", not "this code is safe".
  For vaporOS programs published by us, what the signature promises is a policy to write when we have some.

## What the device checks (`lib/vpm/index.lua`)

With `keys` configured, signatures are **required**, always: a missing or wrong `.sig`, or a signature by an unknown key,
fails with exit 4 and nothing is installed. Without `keys`, nothing is checked (file:// mirrors you built yourself, or
https where TLS is the trust). `meta.json` is verified before any package file, and carries a `serial` (the build
time). The highest serial ever seen is kept in `<libdir>/.vpm/index-serial`, and a lower one is refused: an attacker
cannot swap in an old, vulnerable index after the device has seen a newer one.

Verification is `vsign.verify(sig, msg, pubkey)` in C (Monocypher 4.0.3, pinned in vaporOS `setup.sh`): about 14 KB
of flash on the RP2040. Signing never happens on a device.

## What this does not protect against (be honest)

- **Freeze / rollback before first sight:** an attacker who controls the network can keep serving an old but correctly
  signed index to a device that has never seen a newer one, and can withhold updates indefinitely. The serial only
  stops going backwards. There is no `expires` check yet because the board has no wall clock (prerequisite P8).
- **Single-package rollback:** the serial is checked on `meta.json` only; an old signed package file is accepted.
  Closing that needs per-package hashes in the signed meta (about 150 KB for the full index, too big for a board) or
  a sharded two-level scheme. Not built.
- **Key loss or compromise:** there is no revocation. Rotation means shipping a new key to devices some other way.
  Keep the private key offline; the one used in tests is throwaway.
- **Privacy:** over http the package names you fetch are visible. Package contents are public anyway.

## Measured / unmeasured

Checked on the simulator with real openssl signatures and Monocypher: valid index accepted; wrong key and a package
altered after signing both rejected. Verification time on the RP2040 is **not measured** (no board at hand); expect
about a second per package file. Check before relying on it.
