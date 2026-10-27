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
  local root, origin = source.fetch(rs, dir)
  if not root then done(origin) end
  local entry, why = pkg.analyze(rs, root, origin)
  source.run("rm -rf " .. source.q(dir))
  if not entry then done(why) end
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

if cmd == "emit" then
  local manifest, evaluate = require("manifest"), require("evaluate")
  local mpath, specdir, recdir, out = arg[2], arg[3], arg[4], arg[5]
  local repo = manifest.load(mpath)
  local _, checked = evaluate(repo, specdir)

  -- rockspec-level closure first, so "rejected because of a dependency" is not reported as "not processed"
  local pre = filter.closure(checked)
  for name, c in pairs(checked) do
    if c.ok and pre[name] ~= true then checked[name] = { ok = false, reason = "dep" } end
  end

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
  local status = filter.closure(checked)

  -- modules the firmware provides, for the undeclared-require warning
  local firmware = { lfs = true, lpeg = true, re = true, cjson = true, ["cjson.util"] = true, compat53 = true }
  local function closure_modules(name, seen, set)
    if seen[name] then return end
    seen[name] = true
    local r = records[name]
    if not r then return end
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
    if st ~= true then
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
      local ver = {
        lua = r.lua, deps = r.deps, files = r.files, bin = r.bin, modules = r.modules, host = r.host,
        undeclared_requires = #warn > 0 and warn or nil, luajit = r.luajit, size = r.size,
        origin = r.origin, summary = r.summary, license = r.license, homepage = r.homepage,
      }
      local kind = next(r.bin) and "app" or "lib"
      local shard = name:sub(1, 2):lower():gsub("[^%w]", "_")
      os.execute("mkdir -p " .. source.q(("%s/index/v1/p/%s"):format(out, shard)))
      write(("%s/index/v1/p/%s/%s.json"):format(out, shard, name),
            json.encode({ name = name, kind = kind, versions = { [r.version] = ver } }) .. "\n")
      n = n + 1
      if r.host then hostn = hostn + 1 end
    end
  end
  write(out .. "/index/v1/meta.json", json.encode({
    format = 1, lua = "5.4", packages = n, built = os.date("!%Y-%m-%d"),
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
