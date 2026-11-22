-- Source stage and index emission.
--   lua index-builder/build.lua one  NAME VERSION RSPEC_DIR WORK_DIR RECORD_DIR   process one rock -> RECORD_DIR/NAME.json
--   lua index-builder/build.lua emit MANIFEST RSPEC_DIR RECORD_DIR OUT_DIR         assemble OUT_DIR/index/v1/...
package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local json, sandbox, filter = require("json"), require("sandbox"), require("filter")
local source, pkg, V = require("source"), require("package_analysis"), require("vpm.version")

local cmd = arg[1]

local function write(path, text)
  local f = assert(io.open(path, "wb")); f:write(text); f:close()
end

if cmd == "one" then
  local name, ver, specdir, work, recdir = arg[2], arg[3], arg[4], arg[5], arg[6]
  assert(name:match("^[%w][%w%._%-]*$") and ver:match("^[%w][%w%._%-]*$"), "unsafe name")
  local rec = { name = name, version = ver }
  local function done(status)
    rec.status = status or "ok"
    write(("%s/%s.lua"):format(recdir, name), "return " .. json.lua_literal(rec) .. "\n")
    os.exit(0)
  end
  local f = io.open(("%s/%s-%s.rockspec"):format(specdir, name, ver), "rb")
  local rs = f and sandbox.load(f:read("a"), name)
  if not rs then done("rockspec-error") end
  local ok, reason, info = filter.check(rs)
  if not ok then done(reason) end
  local dir = ("%s/%s-%s"):format(work, name, ver)
  local root, origin
  if info.native.native then
    -- a rock that has to be built: its source rock is the one source (its hash is in the index), so plan and tree are the ones vpm will unpack
    root, origin = source.fetch_srcrock(name, ver, rs, dir)
    if not root then source.run("rm -rf " .. source.q(dir)); root, origin = nil, nil end
  end
  if not root then root, origin = source.fetch(rs, dir) end
  if not root and (origin == "source-download" or origin == "source-ref-missing" or origin == "source-scheme" or origin == "source-extract") then
    source.run("rm -rf " .. source.q(dir))      -- the rock's own source is gone: luarocks.org's copy
    root, origin = source.fetch_srcrock(name, ver, rs, dir)
  end
  if not root then done(origin) end
  local entry, why
  local native = info.native.native and info.native
  if not native then
    entry, why = pkg.analyze(rs, root, origin)
    -- a builtin rock without a module list whose tree holds C is native although the rockspec does not say so
    if not entry and why == "native-source" then native = { native = "c" } end
  end
  if native then
    -- a rock that compiles or runs a build step: no file list (vpm builds it from source); the tree tells what language build systems like make or cmake compile
    local okl, listing = source.run(("cd %s && find . -type f -not -path './.git/*' | head -20000"):format(source.q(root)))
    local tree = {}
    for p in (okl and listing or ""):gmatch("[^\n]+") do
      p = p:gsub("^%./", "")
      if not (p:find("^tests?/") or p:find("^spec/") or p:find("^docs?/") or p:find("^examples?/")) then tree[#tree + 1] = p end
    end
    if why == "native-source" then   -- classify as a make-like build so the tree decides
      local fake = {}
      for k, v in pairs(rs) do fake[k] = v end
      fake.build = { type = "make" }
      native = require("classify").classify(fake, tree)
      native.build = (rs.build or {}).type or "builtin"
    else
      native = require("classify").classify(rs, tree)
    end
    entry, why = { files = {}, bin = {}, modules = {}, requires = {} }, nil
    -- C rocks vpm can build: a compile plan (checked against the unpacked source) and the Lua files of the rock as ordinary files
    if native.native == "c" and native.build == "builtin" and origin.type == "luarocks" then
      local cplan, preason = require("classify").plan(rs)
      if cplan then
        local okv, verr = require("vpm.native").validate(cplan)
        if not okv then cplan, preason = nil, verr end
      end
      if cplan then
        for _, m in ipairs(cplan.modules) do
          for _, srcf in ipairs(m.sources) do
            if not source.run("test -f " .. source.q(root .. "/" .. srcf) .. " -a ! -L " .. source.q(root .. "/" .. srcf)) then cplan, preason = nil, "missing source " .. srcf; break end
          end
          if not cplan then break end
        end
      end
      if cplan then
        local lentry, lwhy = pkg.analyze(rs, root, origin, { skip_native = true })
        if lentry then entry = lentry else cplan, preason = nil, "lua part: " .. tostring(lwhy) end
      end
      native.plan, native.srcdir, native.no_plan_reason = cplan, rs.source and rs.source.dir or nil, (not cplan) and preason or nil
    elseif native.native == "c" and native.build == "builtin" then
      native.no_plan_reason = "no source rock on luarocks.org"
    end
    local bt = (rs.build or {}).type
    if bt == nil or bt == "builtin" or bt == "module" then   -- other build types do not use build.modules for module names
      local seen = {}
      for _, m in ipairs(entry.modules) do seen[m] = true end
      for m in pairs((rs.build or {}).modules or {}) do if type(m) == "string" and not seen[m] then entry.modules[#entry.modules + 1] = m end end
    end
    table.sort(entry.modules)
  end
  -- files that have no stable per-file URL (archives from arbitrary hosts) are kept as content-addressed blobs, served next to the index
  local blobs = os.getenv("VLR_BLOBS")
  if entry and blobs then
    for _, ent in pairs(entry.files) do
      if not source.raw_url(origin, ent.src) then
        local dst = ("%s/%s/%s"):format(blobs, ent.sha256:sub(1, 2), ent.sha256)
        source.run(("mkdir -p %s && cp %s %s"):format(source.q(blobs .. "/" .. ent.sha256:sub(1, 2)), source.q(root .. "/" .. ent.src), source.q(dst)))
      end
    end
  end
  source.run("rm -rf " .. source.q(dir))
  if not entry then done(why) end
  rec.native = native or nil
  rec.host, rec.files, rec.bin, rec.modules, rec.requires, rec.luajit = info.host, entry.files, entry.bin, entry.modules, entry.requires, entry.luajit
  rec.size = entry.size
  rec.deps, rec.lua = {}, nil
  for _, s in ipairs(rs.dependencies or {}) do
    local d = V.parse_dep(s)
    if d and d.name == "lua" then rec.lua = s:gsub("^%s*lua%s*", "") else rec.deps[#rec.deps + 1] = s end
  end
  local o = {}
  for k, v in pairs(origin) do if type(v) ~= "function" then o[k] = v end end
  rec.origin = o
  rec.summary = type(rs.description) == "table" and rs.description.summary or nil
  rec.license = type(rs.description) == "table" and rs.description.license or nil
  rec.homepage = type(rs.description) == "table" and rs.description.homepage or nil
  done("ok")
end

-- lua index-builder/build.lua mirror NAME VERSION WORK_DIR MIRROR_DIR : hash, size and date of the rockspec and the source rock exactly as luarocks.org serves them -> MIRROR_DIR/NAME.lua
if cmd == "mirror" then
  local name, ver, work, outdir = arg[2], arg[3], arg[4], arg[5]
  assert(name:match("^[%w][%w%._%-]*$") and ver:match("^[%w][%w%._%-]*$"), "unsafe name")
  source.run("mkdir -p " .. source.q(work))
  local function one(ext, limit)
    local file, hdr = ("%s/%s-%s.%s"):format(work, name, ver, ext), ("%s/%s-%s.%s.hdr"):format(work, name, ver, ext)
    local url = ("https://luarocks.org/%s-%s.%s"):format(name, ver, ext)
    local ok = source.run(("curl -sSfL -m 120 --max-filesize %d -D %s -o %s %s"):format(limit, source.q(hdr), source.q(file), source.q(url)))
    local res
    if ok then
      local okh, h = source.run("sha256sum " .. source.q(file))
      local _, head = source.run("cat " .. source.q(hdr))
      local _, size = source.run("stat -c %s " .. source.q(file))
      res = okh and { sha256 = h:match("^(%x+)"), size = tonumber(tostring(size):match("%d+")), date = tostring(head):match("[Ll]ast%-[Mm]odified:%s*([^\r\n]+)") }
    end
    source.run(("rm -f %s %s"):format(source.q(file), source.q(hdr)))
    return res
  end
  local rec = { name = name, version = ver, rockspec = one("rockspec", 1000000), src = one("src.rock", 60000000) }
  write(("%s/%s.lua"):format(outdir, name), "return " .. json.lua_literal(rec) .. "\n")
  os.exit(0)
end

if cmd == "emit" then
  local manifest, evaluate = require("manifest"), require("evaluate")
  local mpath, specdir, recdir, out = arg[2], arg[3], arg[4], arg[5]
  local mirrordir = os.getenv("VLR_MIRROR")
  local compatdir = os.getenv("VLR_COMPAT")      -- libtest's per-package results (tools/libtest/summarize.lua with COMPAT_OUT), merged as `vlr`
  local catalogue = {}      -- the `mirror` stage's output, merged into each entry as `luarocks`
  local repo = manifest.load(mpath)
  local _, checked = evaluate(repo, specdir)

  local records = {}
  for name, c in pairs(checked) do
    local f = loadfile(("%s/%s.lua"):format(recdir, name))
    if c.ok and f then
      local rec = f()
      records[name] = rec
      if rec.status ~= "ok" then checked[name] = { ok = false, reason = rec.status } end
    elseif c.ok then
      checked[name] = { ok = false, reason = "not-processed" }
    end
  end
  local status, root = filter.closure(checked)

  -- modules the firmware provides, for the undeclared-require warning
  local firmware = { lfs = true, lpeg = true, re = true, cjson = true, ["cjson.util"] = true, compat53 = true }
  local function closure_modules(name, seen, set)
    if seen[name] then return end
    seen[name] = true
    local r = records[name]
    if not r or r.status ~= "ok" then return end
    for _, m in ipairs(r.modules) do set[m] = true end
    for _, s in ipairs(r.deps) do
      local d = V.parse_dep(s)
      if d then closure_modules(d.name, seen, set) end
    end
  end

  os.execute("mkdir -p " .. source.q(out .. "/index/v1/p"))
  local n, reasons, hostn = 0, {}, 0
  local names = {}
  for name in pairs(checked) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local st = status[name]
    -- a good record whose dependency is unavailable stays visible: the entry says which dependency blocks it (2026-11-22: nothing is hidden because of a dependency)
    local blocked = st == "dep" and records[name] and records[name].status == "ok" and root[name]
    if st ~= true and not blocked then
      local k = tostring(st)
      reasons[k] = (reasons[k] or 0) + 1
    else
      local r = records[name]
      local known = {}
      closure_modules(name, {}, known)
      local warn = {}
      for _, m in ipairs(r.requires) do
        if not known[m] and not known[m:match("^[^.]+")] and not firmware[m] and not firmware[m:match("^[^.]+")] then warn[#warn + 1] = m end
      end
      -- the host this rock needs, from the filter's tag or from what its code requires: vpm hides tagged packages unless the config allows that host
      local host = r.host
      if not host and r.luajit then host = "luajit" end
      if not host then
        local HOSTS = { ngx = "openresty", resty = "openresty", kong = "openresty", vim = "nvim", nvim = "nvim", plenary = "nvim", awful = "awesome", gears = "awesome",
                        wibox = "awesome", naughty = "awesome", beautiful = "awesome", love = "love" }
        for _, m in ipairs(r.requires) do
          local h = HOSTS[m:match("^[^.]+")]
          if h then host = h; break end
        end
      end
      local nat = r.native
      if nat and nat.native == "c" and not nat.plan and not nat.no_plan_reason then   -- C by its source tree but not a builtin build: vpm builds only builtin ones
        local copy = {}
        for k, v in pairs(nat) do copy[k] = v end
        copy.no_plan_reason = "build type " .. tostring(nat.build)
        nat = copy
      end
      local ver = {
        lua = r.lua, deps = r.deps, files = r.files, bin = r.bin, modules = r.modules, host = host,
        undeclared_requires = #warn > 0 and warn or nil, luajit = r.luajit, size = r.size, native = nat,
        luarocks = (function()
          local f = mirrordir and loadfile(("%s/%s.lua"):format(mirrordir, name))
          local m = f and f()
          if not (m and (m.rockspec or m.src)) then return nil end
          local src = m.src and { sha256 = m.src.sha256, size = m.src.size, date = m.src.date, url = ("https://luarocks.org/%s-%s.src.rock"):format(name, r.version) } or nil
          -- a C rock's plan was made against the source rock the builder unpacked: that hash is the one vpm must see
          if src and r.native and r.native.plan and r.origin and r.origin.type == "luarocks" then src.sha256, src.size = r.origin.sha256, r.origin.size or src.size end
          return { rockspec = m.rockspec, src = src, date = (m.rockspec or m.src or {}).date }
        end)(),
        vlr = (function()
          local f = compatdir and loadfile(("%s/%s.lua"):format(compatdir, name))
          return f and f() or nil
        end)(),
        blocked_by = blocked and { name = blocked.name, reason = blocked.reason } or nil,
        origin = r.origin, summary = r.summary, license = r.license, homepage = r.homepage,
      }
      local files = {}
      for dest, ent in pairs(r.files) do
        files[dest] = { sha256 = ent.sha256, size = ent.size, url = source.raw_url(r.origin, ent.src) or ("blob:" .. ent.sha256) }
      end
      ver.files = files
      do   -- one line per package for `vpm search`
        local cls = r.native and r.native.native or "pure"
        local w = ver.vlr and (ver.vlr.status == "ok" and "ok" or ver.vlr.status == "fail" and "fail" or ver.vlr.status == "partial" and "partial") or nil
        catalogue[#catalogue + 1] = json.compact({ n = name, v = r.version, s = ver.summary, c = cls, h = host,
          b = require("vpm.native").buildable(ver) and 1 or nil, w = w })
      end
      local kind = next(r.bin) and "app" or "lib"
      local shard = name:sub(1, 2):lower():gsub("[^%w]", "_")
      os.execute("mkdir -p " .. source.q(("%s/index/v1/p/%s"):format(out, shard)))
      write(("%s/index/v1/p/%s/%s.json"):format(out, shard, name),
            json.encode({ name = name, kind = kind, versions = { [r.version] = ver } }) .. "\n")
      n = n + 1
      if host then hostn = hostn + 1 end
    end
  end
  table.sort(catalogue)
  write(out .. "/index/v1/search.jsonl", table.concat(catalogue, "\n") .. "\n")
  if os.getenv("VLR_BLOBS") then os.execute(("mkdir -p %s/blobs && cp -r %s/. %s/blobs/"):format(source.q(out), source.q(os.getenv("VLR_BLOBS")), source.q(out))) end
  write(out .. "/index/v1/meta.json", json.encode({
    format = 1, lua = "5.4", packages = n, built = os.date("!%Y-%m-%d"), serial = os.time(),
    provided = filter.provided, stub = filter.stub }) .. "\n")
  local rl = {}
  for k, c in pairs(reasons) do rl[#rl + 1] = { k, c } end
  table.sort(rl, function(a, b) return a[2] > b[2] end)
  print(("index: %d packages written (%d tagged host), %d rejected"):format(n, hostn, #names - n))
  for i = 1, math.min(14, #rl) do print(("  %5d  %s"):format(rl[i][2], rl[i][1])) end
end

if cmd == "todo" then      -- rocks that passed the rockspec stage (with closure) and have no record yet
  local manifest, evaluate = require("manifest"), require("evaluate")
  local repo = manifest.load(arg[2])
  local names, checked = evaluate(repo, arg[3])
  local pre = filter.closure(checked)
  for _, name in ipairs(names) do
    local c = checked[name]
    if c and c.ok and pre[name] == true then
      local f = io.open(("%s/%s.lua"):format(arg[4], name), "rb")
      if f then f:close() else print(name, c.version) end
    end
  end
end
