# Publishing to luarocks.org (research and implementation, 2026-11-22)

**Implemented:** `vpm publish` (dry run: checks the git remote and tag, prints the rockspec) and `vpm publish --upload` (check_rockspec, confirmation, TFA token from `VPM_LUAROCKS_TFA`, multipart upload). Tested against a fake server only;
the real server is untested until the user provides a key (first upload: a throwaway module name). Decisions taken (user asked for advice): source = the git remote at a tag that must exist and be pushed (`git+https://...`, never an archive made by vpm); key only from `VPM_LUAROCKS_KEY`.
Only pure-Lua projects (builtin build, one module per .lua file); a project with C code is not handled yet.

Decision (user): publish through luarocks.org itself unless a feature of ours needs more. Source: https://luarocks.org/docs/api (read 2026-11-22) and the incident report it links.

## What the API offers
Base `https://luarocks.org`. Auth: the key goes in the path (`/api/1/KEY/...`, legacy) or, recommended, `Authorization: Bearer KEY` with the literal word `bearer` in the key slot.
Keys come from `/settings/api-keys`. Errors are `{"errors": [...]}`; 401 bad key, 403 revoked/suspended/TFA required, 429 too many failed TFA attempts.

| endpoint | what |
|---|---|
| `GET /api/tool_version` | `{"version": "3.0.0"}`, no auth |
| `GET /api/1/:key/status` | `{user_id, created_at}`, checks a key |
| `GET /api/1/:key/check_rockspec?package=&version=` | `{module, version}`; `version` null when that version does not exist yet |
| `POST /api/1/:key/verify_tfa` (`code`) | `{success, tfa_token, expires}`; the token lasts 15 minutes, is bound to the key |
| `POST /api/1/:key/upload` (multipart `rockspec_file`, `tfa_token` or `X-TFA-Token`) | creates the module or adds a version: `{module, version, module_url, manifests, is_new}` |
| `POST /api/1/:key/upload_rock/:version_id` (multipart `rock_file`) | attaches a built `.rock` to an existing version |

There are **no read endpoints** in the documented API (no listing, no JSON module info, no dates, no download counts) and **no delete**. Reading stays what our crawler does: `manifest-5.4(.json/.zip)`, `NAME-VER.rockspec`,
`NAME-VER.src.rock`, with `Last-Modified` for dates. Not documented, so unverified until tried with a real key: whether the server keeps the source (`.src.rock` exists on the site for older rocks), whether `source.url`
must be reachable at upload, whether a version can be replaced, size limits, name ownership rules.

## What vpm publish would do
1. Read `vpm.lua` (name, version, deps, description, license, `kind`, bin) and the files it lists; refuse when the working tree is not what a tag/archive URL will serve.
2. Generate a rockspec: `package`, `version` (`X.Y-N`), `source.url` (a tag archive or `git+https` URL of the project, given by the user or derived from the repository), `dependencies`, `build` of type `builtin`
   with the Lua modules (and C modules for a C project).
3. Show the rockspec and ask. Then `check_rockspec` (is the version taken?), `upload` with the key from `VPM_LUAROCKS_KEY` or the config file (never an argument: it ends up in shell history), TFA token when asked.
4. Print `module_url`.
Not needed for the index: we do not upload `.rock` files; consumers use the rockspec's `source.url` or luarocks.org's source rock.

## Security context
The incident report (https://luarocks.org/security-incident-september-2026) says uploads between 9 July and 20 August 2026 abused a code-execution flaw in rockspec parsing (bytecode rockspecs); all API keys were revoked and the server now loads rockspecs in text mode.
Consequences for us: (a) our builder already loads rockspecs with `load(text, name, "t", sandbox_env)` (text only, no bytecode), keep it that way; (b) a rockspec is code from the network: vpm never evaluates one on the client,
the signed index carries the evaluated fields; (c) this is why the signed hash mirror matters: a version's bytes are pinned by our signature, not by luarocks.org's say-so.

## Decided (advice accepted by default; change on request)
- Where `source.url` comes from for a project that is not on a forge, and whether vpm should create the archive (tag + `git archive`) itself.
- Testing needs a real account and key: the user must create the key; I will not handle one without being given it, and the first upload should be a throwaway module name.
