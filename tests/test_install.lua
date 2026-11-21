package.path = "lib/?.lua;index-builder/?.lua;tests/lib/?.lua;" .. package.path
local fs, hash = require("vpm.fs"), require("vpm.hash")
local Installer, Index, transport = require("vpm.installer"), require("vpm.index"), require("vpm.transport")
local resolver, json, decode = require("vpm.resolver"), require("json"), require("json_decode")

local base = os.tmpname(); os.remove(base); assert(fs.mkdirp(base))
local mirror, sysroot = base .. "/mirror", base .. "/sys"

local publish = require("mirror").new(mirror)

publish{
  lpeglike = { versions = { ["1.0-1"] = { files = { ["lpeglike.lua"] = "return 'lpeglike'" } } } },
  ansicolors = { versions = { ["1.0.2-3"] = { files = { ["ansicolors.lua"] = "return 'colors'" } } } },
  mathx = { versions = { ["1.0-1"] = { files = { ["mathx/init.lua"] = "return 1", ["mathx/extra.lua"] = "return 2" },
                                       deps = { "lpeglike >= 1.0" } },
                         ["2.0-1"] = { files = { ["mathx/init.lua"] = "return 20" }, deps = { "lpeglike >= 1.0" } } } },
  notes = { kind = "app", versions = { ["0.3-1"] = { files = { ["notes.lua"] = "print('notes')", ["lib/util.lua"] = "return {}" },
                                                       deps = { "mathx" }, bin = { notes = "notes.lua" } } } },
  broken = { versions = { ["1.0-1"] = { files = { ["broken.lua"] = "x" }, badhash = true } } },
  bundle = { versions = { ["1.0-1"] = { files = { ["bundle.lua"] = "b" }, deps = { "ansicolors", "broken" } } } },
  evil = { versions = { ["1.0-1"] = { files = { ["ok.lua"] = "x" } } } },
}
-- an index entry that tries to escape its directory
do
  local f = mirror .. "/index/v1/p/ev/evil.json"
  local doc = decode(fs.read(f)); local m = doc.versions["1.0-1"]
  m.files["../../escape.lua"] = m.files["ok.lua"]
  assert(fs.write(f, json.encode(doc)))
end

local cfg = { libdir = sysroot .. "/lib", appdir = sysroot .. "/apps", bindir = sysroot .. "/bin", local_root = base .. "/proj/lua_modules" }
local idx = Index.new{ base = "file://" .. mirror .. "/index/v1", transport = transport, decode = decode }
local inst = Installer.new{ cfg = cfg, transport = transport, index = idx, now = function() return 0 end }

local function install(requests, scope, extra)
  local o = { requests = requests, scope = scope or "global", provided = {}, deps = "auto",
              installed = { global = inst:state("global"):installed_view(), ["local"] = inst:state("local"):installed_view() },
              index = function(n) return idx:resolver_view(n) end }
  for k, v in pairs(extra or {}) do o[k] = v end
  local plan, err = resolver.resolve(o)
  if not plan then return nil, err end
  local req = {}
  for _, r in ipairs(requests) do req[r.name] = r.constraint or "" end
  return inst:apply(plan, req)
end
local function exists(p) return fs.exists(p) end

-- 1. library with a dependency: files, records, world, hashes
assert(install({ { name = "mathx", constraint = "== 1.0-1" } }))
assert(fs.read(cfg.libdir .. "/mathx/init.lua") == "return 1" and exists(cfg.libdir .. "/lpeglike.lua"))
local g = inst:state("global")
local rec = g:get("mathx")
assert(rec.version == "1.0-1" and rec.reason == "world" and rec.deps.lpeglike == ">= 1.0" and rec.resolved.lpeglike == "1.0-1")
assert(g:get("lpeglike").reason == "dep" and g:world().mathx == "== 1.0-1" and not g:world().lpeglike)
assert(#inst:check("global") == 0 and not exists(g.dir .. "/lock") and not exists(g.dir .. "/staging"))

-- 2. check notices tampering
fs.write(cfg.libdir .. "/lpeglike.lua", "evil")
local problems = inst:check("global")
assert(#problems == 1 and problems[1]:find("modified"))
fs.write(cfg.libdir .. "/lpeglike.lua", "return 'lpeglike'")

-- 3. remove refuses while needed, then works; empty directories are pruned
local ok, err, code = inst:remove({ "lpeglike" }, "global")
assert(not ok and err:find("needed by mathx") and code == 3)
assert(inst:remove({ "mathx" }, "global") and not exists(cfg.libdir .. "/mathx") and not g:get("mathx") and not g:world().mathx)
assert(exists(cfg.libdir .. "/lpeglike.lua") and g:get("lpeglike"))   -- dependencies stay (vpm clean removes them)

-- 4. upgrade replaces the old version's files
assert(install({ { name = "mathx", constraint = "== 1.0-1" } }) and exists(cfg.libdir .. "/mathx/extra.lua"))
assert(install({ { name = "mathx", constraint = "== 2.0-1" } }, "global", { installed = { global = {}, ["local"] = {} } }))
assert(fs.read(cfg.libdir .. "/mathx/init.lua") == "return 20" and not exists(cfg.libdir .. "/mathx/extra.lua"))
assert(g:get("mathx").version == "2.0-1")

-- 5. integrity failure: nothing changes, staging is cleaned, lock released (exit 4)
ok, err, code = install({ { name = "broken" } })
assert(not ok and err:find("sha256 mismatch") and code == 4)
assert(not exists(cfg.libdir .. "/broken.lua") and not g:get("broken") and not exists(g.dir .. "/lock") and not exists(g.dir .. "/staging"))

-- 6. an index entry with a path escaping the directory is refused before anything is written
ok, err = install({ { name = "evil" } })
assert(not ok and err:find("unsafe file path"), tostring(err))
assert(not exists(cfg.libdir .. "/ok.lua") and not exists(sysroot .. "/escape.lua") and not exists(base .. "/escape.lua"))

-- 7. an unmanaged file is never overwritten
fs.write(cfg.libdir .. "/ansicolors.lua", "mine")
ok, err = install({ { name = "ansicolors" } })
assert(not ok and err:find("not managed by vpm") and fs.read(cfg.libdir .. "/ansicolors.lua") == "mine")
fs.remove(cfg.libdir .. "/ansicolors.lua")

-- 8. program: files under appdir, launcher in bindir, shared dependency reused
assert(install({ { name = "notes" } }))
assert(fs.read(cfg.appdir .. "/notes/notes.lua") == "print('notes')" and exists(cfg.appdir .. "/notes/lib/util.lua"))
local launcher = fs.read(cfg.bindir .. "/notes")
assert(launcher:find("^#!/bin/lua") and launcher:find(cfg.appdir .. "/notes/notes.lua", 1, true))
assert(g:get("notes").kind == "app" and g:get("notes").launchers.notes == cfg.bindir .. "/notes")
assert(not exists(cfg.libdir .. "/notes.lua"))                      -- program files stay out of the module path
assert(inst:remove({ "notes" }, "global") and not exists(cfg.appdir .. "/notes") and not exists(cfg.bindir .. "/notes"))

-- 9. local scope: files under the project's lua_modules, separate records
assert(install({ { name = "ansicolors" } }, "local"))
local l = inst:state("local")
assert(fs.read(cfg.local_root .. "/ansicolors.lua") == "return 'colors'" and l:get("ansicolors").scope == "local")
assert(not g:get("ansicolors"))

-- 10. a crashed run leaves a lock that blocks the next one and that check reports
fs.write(g.dir .. "/lock", "1")
ok, err = install({ { name = "ansicolors" } })
assert(not ok and err:find("another vpm run"))
assert(inst:check("global")[1]:find("stale lock"))
fs.remove(g.dir .. "/lock")

-- 11. fresh installs are written in place: no staging renames for packages, only the world file
fs.remove(cfg.local_root .. "/ansicolors.lua"); inst:remove({ "ansicolors" }, "local")
local renames, real_rename = 0, fs.rename
fs.rename = function(a, b) renames = renames + 1; return real_rename(a, b) end
assert(install({ { name = "ansicolors" } }))
assert(renames == 1, "renames: " .. renames)               -- only world.lua
-- 11b. an upgrade still goes through staging, so a failed download keeps the working version
publish{ mathx = { versions = { ["3.0-1"] = { files = { ["mathx/init.lua"] = "return 30" }, deps = { "lpeglike >= 1.0" }, badhash = true } } } }
idx.cache = {}
renames = 0
ok, err, code = install({ { name = "mathx", constraint = "== 3.0-1" } })
assert(not ok and code == 4 and fs.read(cfg.libdir .. "/mathx/init.lua") == "return 20" and g:get("mathx").version == "2.0-1")
fs.rename = real_rename
-- 11c. one bad package in a plan removes the files the others already wrote in place
fs.remove(cfg.libdir .. "/ansicolors.lua"); g:delete("ansicolors")
ok, err, code = install({ { name = "bundle" } })
assert(not ok and code == 4 and err:find("sha256"))
assert(not exists(cfg.libdir .. "/ansicolors.lua") and not exists(cfg.libdir .. "/bundle.lua") and not g:get("ansicolors"))
assert(not exists(g.dir .. "/lock") and not exists(g.dir .. "/staging"))

-- 11d. a crash: the lock (journal) lists files; repair removes those without a complete record
fs.write(cfg.libdir .. "/half.lua", "partial"); fs.mkdirp(cfg.libdir .. "/hd"); fs.write(cfg.libdir .. "/hd/x.lua", "partial")
fs.write(g.dir .. "/lock", "half\t" .. cfg.libdir .. "/half.lua\nhalf\t" .. cfg.libdir .. "/hd/x.lua\nmathx\t" .. cfg.libdir .. "/mathx/init.lua\n")
assert(inst:check("global")[1]:find("stale lock"))
assert(inst:repair("global") == 2)
assert(not exists(cfg.libdir .. "/half.lua") and not exists(cfg.libdir .. "/hd") and not exists(g.dir .. "/lock"))
assert(fs.read(cfg.libdir .. "/mathx/init.lua") == "return 20")       -- a complete package is never touched

-- 12. record serialisation round-trips
local State = require("vpm.state")
local t = { name = "x", files = { ["a b.lua"] = "h", ["c/d.lua"] = "i" }, n = 3, flag = true, s = 'q"\n' }
local back = load(State.serialise(t), "=t", "t", {})()
assert(back.files["a b.lua"] == "h" and back.n == 3 and back.flag and back.s == 'q"\n')

fs.rmtree(base)
print("install ok")

-- download retries: transient failures are repeated with a fresh file and hash, certificate failures and 404s are not
do
  local calls, slept = 0, {}
  local function make(script)
    return Installer.new{ cfg = cfg, index = idx, now = function() return 0 end, tries = 4, sleep = function(s) slept[#slept + 1] = s end,
      transport = { get = function(url, sink)
        calls = calls + 1
        local step = table.remove(script, 1)
        if step.partial then sink(step.partial) end    -- bytes that arrive before the connection dies must not end up in the file
        return step.status, step.err, step.body and sink(step.body)
      end } }
  end
  local path = os.tmpname()
  local inst2 = make{ {status = 429, err = "Too Many Requests", partial = "junk"}, {status = 502, err = "timeout", partial = "more junk"}, {status = 200, body = "good"} }
  local status, err, n, hex = inst2:download("http://x/f", path)
  assert(status == 200 and n == 4 and io.open(path, "rb"):read("a") == "good", "retried with a fresh file")
  assert(hex == require("vpm.hash").hex("good") and calls == 3 and #slept == 2 and slept[2] > slept[1], "backoff grows")

  calls, slept = 0, {}
  status = make{ {status = 502, err = "certificate is not trusted (unknown issuer)"} }:download("https://x/f", path)
  assert(status == 502 and calls == 1 and #slept == 0, "certificate failures are not retried")
  calls = 0
  status = make{ {status = 404} }:download("http://x/f", path)
  assert(status == 404 and calls == 1, "404 is not retried")
  calls = 0
  status = make{ {status = 503}, {status = 503}, {status = 503}, {status = 503} }:download("http://x/f", path)
  assert(status == 503 and calls == 4, "gives up after tries attempts")
  os.remove(path)
end

-- blob: URLs resolve against the index host
do
  local seen
  local inst3 = Installer.new{ cfg = cfg, index = { base = "https://example.org/pkgs/index/v1" }, now = function() return 0 end, tries = 1,
    transport = { get = function(url, sink) seen = url; sink("x"); return 200 end } }
  local sha = ("ab"):rep(32)
  local path = os.tmpname()
  assert(inst3:download("blob:" .. sha, path) == 200)
  assert(seen == "https://example.org/pkgs/blobs/ab/" .. sha, seen)
  assert(inst3:download("blob:abcd", path) == 400, "a malformed blob reference is refused")
  os.remove(path)
end
