# vpm: a package manager for Lua

vpm installs libraries and programs, with their dependencies, from [luarocks.org](https://luarocks.org). It runs on [vlr](https://github.com/tibocub/vapor-lua-runtime)
(the Vapor Lua Runtime) on Linux, macOS, Windows, and on small boards such as the RP2040 (about 190 KB of RAM). vlr + vpm is meant to be to Lua what
Node + npm are to JavaScript. vpm is written in Lua and is the first real vlr application.

**Status: working on Linux, in daily use against the real index; young.** See [docs/status.md](docs/status.md) for what is verified and what is not.

## Quickstart

You need [vlr](https://github.com/tibocub/vapor-lua-runtime) and a C compiler only for rocks with C code.

```sh
git clone https://github.com/tibocub/vapor-package-manager vpm
alias vpm='vlr /path/to/vpm/bin/vpm.lua'

vpm search json --here --works     # what installs on this machine and is known to run on vlr
vpm i inspect                      # into ./lua_modules (vlr finds it there; add -g for ~/.local/share/vpm)
vpm ls
```

With no config file vpm uses the public signed index (`https://tibocub.github.io/vpm-index/index/v1`) and its key.

## Using it

```
vpm search WORDS [--pure] [--native=none|c|any] [--host=nvim,love|--no-host] [--works] [--here] [--all]
vpm info PKG                  versions, dependencies, native class, why a package cannot be installed here
vpm install (i) [PKG[@VER]]   install; with no argument, what ./vpm.lua asks for (writes vpm-lock.lua)
vpm remove (rm) PKG   vpm list (ls)   vpm upgrade (u)   vpm why PKG   vpm world   vpm check [--repair]
vpm init                      create a vpm.lua (name, version, deps, entry point)
vpm bundle PKG... --dir=D     fetch C rocks and write D/bundle.conf to compile them into vlr (make CONF_EXTRA=D/bundle.conf)
vpm publish [--upload]        publish this project to luarocks.org (dry run by default; key in VPM_LUAROCKS_KEY)
```
Options: `-g` global scope, `-n` plan only, `-y` no questions, `--deps=auto|global|local`, `--index=URL`, `--allow-scripts`.
Every change prints a plan first; nothing is touched before it is accepted. Version syntax: `name@1` (any 1.x), `name@1.2`, `name@">=1.0,<2"`.

A project's `vpm.lua` lists what it wants:

```lua
return { name = "mytool", version = "0.1.0", kind = "app", bin = { mytool = "main.lua" },
         deps = { penlight = "~> 1.13", lpeg = ">= 1.0" } }
```

## What the index says about every rock

- **pure** Lua: files are copied, each checked against a sha256.
- **c**: built with the local C compiler against vlr's own headers and loaded as a `.so`. **build** rocks that use `make` or `cmake` are built from a plan the index records,
  inside a bubblewrap sandbox (no network, read-only system), or with `--allow-scripts`. C++, Rust and `command` builds are listed but not built.
- **host** rocks (Neovim, OpenResty, LOVE, ...) are tagged; **vlr:ok / partial / fails** records whether the rock loaded in a sandbox on vlr.

## Trust

The index is a signed (ed25519) mirror of hashes and dates for every rock, so a download over plain HTTP is still verified and a rock cannot change under a locked version.
`vpm-lock.lua` pins exact versions and a digest per package.

## Repository layout

```
bin/vpm.lua       entry point            lib/vpm/        the client (resolver, installer, index, native builds, commands in cmd/)
index-builder/    builds the index       tools/          index publishing and checking, board deployment, library compatibility runs
tests/            run with: VLR=/path/to/vlr sh tests/run.sh
docs/             documentation: start at docs/README.md
```

## Contributing

`VLR=/path/to/vlr sh tests/run.sh` runs the 16 test files (all offline). Keep source files small and loaded lazily: the RP2040 budget is in
[docs/ram-budget.md](docs/ram-budget.md). Changes to the index format or to what is signed need a note in [docs/decisions.md](docs/decisions.md).

## License

MIT
