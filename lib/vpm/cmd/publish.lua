-- vpm publish [--tag=T] [--source=URL] [--revision=N] [--upload] [-y]
-- Publishes the project in the current directory to luarocks.org (docs/publishing.md). Without --upload it only checks everything and prints the rockspec it would send.
-- The source is the project's git remote at a tag that must exist and be pushed; vpm never builds or hosts an archive. The API key is read from VPM_LUAROCKS_KEY only.
local fs = require("vpm.fs")
local localsrc = require("vpm.localsrc")
local rockspec = require("vpm.rockspec")
local native = require("vpm.native")

local function sq(s) return native.shq(s) end

return function(ctx, args)
  local dir = ctx.cwd
  local entry, lerr = localsrc.load(dir)
  if not entry then ctx.err("%s", lerr); return 1 end
  local f = ctx.flags
  local ver, meta = next(entry.versions)
  local manifest = assert(load(fs.read(dir .. "/vpm.lua"), "=vpm.lua", "t", {}))()
  if entry.kind == "lib" and manifest.kind == "app" then ctx.err("inconsistent manifest"); return 1 end
  local files = {}
  for dest in pairs(meta.files) do files[#files + 1] = dest end
  table.sort(files)
  if manifest.kind == "app" and next(manifest.bin or {}) == nil then ctx.err("an app needs a bin table in vpm.lua"); return 1 end

  local git = ctx.env.git or function(a)
    local p = io.popen(("cd %s && GIT_TERMINAL_PROMPT=0 git %s 2>&1"):format(sq(dir), a))
    local o = p:read("a"); local ok, _, code = p:close()
    return o, ok and 0 or (code or 1)
  end

  local url = f.source
  if not url then
    local o, code = git("remote get-url origin")
    if code ~= 0 then ctx.err("no git remote 'origin' here: pass --source=URL (a public git+https URL)"); return 1 end
    local uerr
    url, uerr = rockspec.source_url(o)
    if not url then ctx.err("%s", uerr); return 1 end
  end
  local tag = f.tag
  if not tag then
    for _, t in ipairs{ "v" .. manifest.version, manifest.version } do
      local _, code = git("rev-parse -q --verify " .. sq("refs/tags/" .. t))
      if code == 0 then tag = t; break end
    end
    if not tag then ctx.err("no git tag v%s or %s: tag the release and push it (git tag v%s && git push origin v%s)", manifest.version, manifest.version, manifest.version, manifest.version); return 1 end
  end
  local _, pushed = git("ls-remote --exit-code --tags origin " .. sq("refs/tags/" .. tag))
  if pushed ~= 0 then ctx.err("tag %s is not on the remote 'origin': push it first (git push origin %s)", tag, tag); return 1 end

  local text, rver = rockspec.generate(manifest, files, { url = url, tag = tag }, tonumber(f.revision))
  local name = manifest.name
  ctx.out("%s %s from %s at tag %s", name, rver, url, tag)
  if not f.upload then
    ctx.out("%s", text)
    ctx.out("(dry run: nothing sent. Set VPM_LUAROCKS_KEY and add --upload to publish)")
    return 0
  end

  local key = ctx.env.getenv and ctx.env.getenv("VPM_LUAROCKS_KEY") or os.getenv("VPM_LUAROCKS_KEY")
  if not key or key == "" then ctx.err("VPM_LUAROCKS_KEY is not set (create a key at https://luarocks.org/settings/api-keys)"); return 1 end
  local server = (ctx.cfg and ctx.cfg.luarocks_server) or "https://luarocks.org"
  local http = ctx.env.http or require("std.http")
  local auth = { Authorization = "Bearer " .. key }
  local function json(body)
    local ok, cj = pcall(require, "cjson.safe")
    return ok and cj.decode(body or "") or nil
  end

  local r, err = http.request{ url = ("%s/api/1/bearer/check_rockspec?package=%s&version=%s"):format(server, name, rver), headers = auth }
  if not r then ctx.err("luarocks.org: %s", tostring(err)); return 4 end
  if r.status == 401 or r.status == 403 then ctx.err("luarocks.org refused the key (%d): create a new one at /settings/api-keys", r.status); return 4 end
  local chk = json(r.body)
  if chk and type(chk.version) == "table" then ctx.err("%s %s is already on luarocks.org: bump the version or the revision (--revision=N)", name, rver); return 1 end
  ctx.out("%s", chk and type(chk.module) == "table" and "adds a version to an existing module" or "creates a new module")
  if not f.yes and not ctx.ask("upload " .. name .. " " .. rver .. " to " .. server .. "?") then ctx.out("not uploaded"); return 1 end

  local hdr = { Authorization = auth.Authorization }
  local tfa = ctx.env.getenv and ctx.env.getenv("VPM_LUAROCKS_TFA") or os.getenv("VPM_LUAROCKS_TFA")
  if tfa and tfa ~= "" then
    local t = http.request{ url = server .. "/api/1/bearer/verify_tfa", method = "POST", headers = { Authorization = auth.Authorization, ["Content-Type"] = "application/x-www-form-urlencoded" }, body = "code=" .. tfa }
    local tj = t and json(t.body)
    if not (tj and type(tj.tfa_token) == "string") then ctx.err("two-factor code refused"); return 4 end
    hdr["X-TFA-Token"] = tj.tfa_token
  end
  local boundary = "----vpm" .. tostring(os.time()) .. tostring(math.random(1e9))
  hdr["Content-Type"] = "multipart/form-data; boundary=" .. boundary
  local body = ("--%s\r\nContent-Disposition: form-data; name=\"rockspec_file\"; filename=\"%s-%s.rockspec\"\r\nContent-Type: text/plain\r\n\r\n%s\r\n--%s--\r\n"):format(boundary, name, rver, text, boundary)
  r, err = http.request{ url = server .. "/api/1/bearer/upload", method = "POST", headers = hdr, body = body }
  if not r then ctx.err("luarocks.org: %s", tostring(err)); return 4 end
  local res = json(r.body)
  if r.status ~= 200 or not res then
    local why = res and res.errors and table.concat(res.errors, "; ") or tostring(r.reason or r.status)
    ctx.err("upload refused (%s): %s", tostring(r.status), why)
    return 4
  end
  ctx.out("published: %s", tostring(res.module_url))
  return 0
end
