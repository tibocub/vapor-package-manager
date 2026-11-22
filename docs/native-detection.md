# Native code detection (2026-11-22)

`index-builder/classify.lua` says what installing a rock takes. Nothing is rejected for being native: the index records the class and vpm shows it, so someone on a device without a
C compiler can tell which libraries will work.

| class   | meaning                                                                                              | needs on the machine           |
|---------|------------------------------------------------------------------------------------------------------|--------------------------------|
| pure    | only Lua files are installed                                                                         | nothing                        |
| `c`     | every compiled source is C (`.c`/`.h`); may also name system libraries (`external`)                  | a C compiler, headers of `external` |
| `build` | a build step (make, command, a build-backend plugin) but no compiled code anywhere in the source tree | the tool (make, the backend rock) |
| `other` | C++, Objective-C, Rust, Go, assembly, Fortran, prebuilt binaries, or nothing says what is compiled (`unknown_language`) | depends: `langs` lists what was seen |

Fields: `native`, `langs`, `build` (rockspec build type), `external` (names from `external_dependencies`), `build_deps` (`build_dependencies`, e.g. `luarocks-build-luke`), `prebuilt`, `unknown_language`.
Builtin rocks are classified from the rockspec alone (it lists every source). make/cmake/command/plugin builds hide their sources, so the builder lists the unpacked tree (without tests/docs/examples)
and reads the languages from file extensions. Shortcut: vendored third-party code in the tree counts, so a rock that vendors C++ but builds C is called `other`.
Native rocks carry no file list yet: vpm shows them and says a build is needed (native builds come later).

## Checking the checker (`tools/classify-audit.lua`)
`stats` classifies every rockspec; `pick` draws seeded random rocks; `one` fetches a rock's source and prints what the rockspec says next to what the tree contains.
First run (90 random rocks) found two classifier bugs, both fixed and covered by `tests/test_classify.lua`: `incdirs`/`defines`/`libdirs` lists were read as source files
(`"lua-compat-5.3"` looked like a `.3` file, so plain C rocks were "other"), and a make/command rock with nothing to compile was "other" instead of `build`.
Second run (239 distinct random rocks, 199 with a fetchable tree) after the fixes: for the 41 rocks with an opaque build type, `c` matched 10 of 10, `other` 21 of 21, and the
remaining 10 are `build` or prebuilt-binary rocks whose tree has no source code (the intended answer). For the builtin rocks the rockspec is exact; in 9 the repository holds native code the rockspec does not build
(the C lives in a dependency rock, or other-language tooling): correctly pure.
Not a classifier problem but found by the same run:
- 40 of 239 sources could not be fetched (16 download failures, 14 missing tags/branches, 10 `git://`/ssh URLs): about 17% of rocks have dead or unusable upstreams. luarocks.org hosts `.src.rock` archives: fall back to them.
- the file analyzer calls any non-`.lua` entry of `install.lua` native (Teal `.d.tl` type files, for example): it should accept data files. Open.
