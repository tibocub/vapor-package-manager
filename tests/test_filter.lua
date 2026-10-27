package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local sandbox, filter = require("sandbox"), require("filter")

local function spec(extra)
  return 'package="demo"\nversion="1.0-1"\nsource={url="https://example.org/demo.tar.gz"}\n' .. (extra or "")
end
local function check(text)
  local rs, err = sandbox.load(text, "t"); assert(rs, err)
  return filter.check(rs)
end
local function accepts(text) local ok, r = check(text); assert(ok, "expected accept, got " .. tostring(r)) end
local function rejects(text, reason)
  local ok, r = check(text); assert(not ok, "expected reject " .. reason)
  assert(r:find(reason, 1, true) == 1, "reason " .. tostring(r) .. " ~= " .. reason)
end

-- accepted
accepts(spec('build={type="builtin",modules={demo="demo.lua",["demo.x"]="src/x.lua"}}'))
accepts(spec('build={type="none"}'))
accepts(spec('build={modules={demo="demo.lua"}}'))                              -- builtin by default
accepts(spec('dependencies={"lua >= 5.1","lpeg >= 1.0"}'))                      -- lpeg is provided by the firmware
accepts(spec('dependencies={"lua>=5.1, <5.5"}'))
accepts(spec('build={install={bin={tool="bin/tool.lua"}}}'))
accepts(spec('if true then build={modules={demo="demo.lua"}} end'))             -- rockspecs may contain logic

-- rejected, one rule each
rejects(spec('build={type="make"}'), "build-type:make")
rejects(spec('build={type="cmake"}'), "build-type:cmake")
rejects(spec('build={modules={demo={sources={"demo.c"}}}}'), "native-source")
rejects(spec('build={modules={demo="src/demo.c"}}'), "native-source")
rejects(spec('build={modules={demo={sources={"a.lua","b.cpp"}}}}'), "native-source")
rejects(spec('build={platforms={unix={modules={demo="demo.c"}}}}'), "native-source")
rejects(spec('external_dependencies={OPENSSL={header="openssl/ssl.h"}}'), "external-deps")
rejects(spec('build={libraries={"m"}}'), "native-flags")
rejects(spec('build={install={lib={demo="demo.so"}}}'), "install-lib")
rejects(spec('dependencies={"lua >= 5.1, < 5.4"}'), "lua-version")
rejects(spec('dependencies={"lua ~> 5.1"}'), "lua-version")                       -- LuaRocks prefix match: 5.1.x only
rejects('package="demo"\nversion="1"\n', "no-source-url")
-- host-application rocks are accepted but tagged
local function host(text) local rs = assert(sandbox.load(text, "t")); local ok, _, info = filter.check(rs); assert(ok); return info.host end
assert(host(spec('description={labels={"neovim"}}')) == "nvim")
assert(host(spec('dependencies={"lua-resty-http"}')) == "openresty")
assert(host('package="x.nvim"\nversion="1"\nsource={url="u"}\n') == "nvim")
assert(host(spec('')) == nil)
-- compat53 is a provided stub on 5.4
accepts(spec('dependencies={"compat53 >= 0.3"}'))

-- closure: dependencies on rejected rocks, provided libraries and their versions
local function chk(text) local rs = assert(sandbox.load(text, "t")); local ok, r, info = filter.check(rs)
  return ok and { ok = true, deps = info.deps } or { ok = false, reason = r } end
local set = {
  good   = chk(spec('dependencies={"lpeg >= 0.12", "compat53"}')),
  needsgood = chk(spec('dependencies={"good"}')),
  native = chk(spec('build={type="make"}')),
  needsnative = chk(spec('dependencies={"native"}')),
  deep   = chk(spec('dependencies={"needsnative"}')),
  oldprov = chk(spec('dependencies={"lpeg < 1.0"}')),   -- firmware has lpeg 1.1.0
  missing = chk(spec('dependencies={"nosuchrock"}')),
}
local status, root = filter.closure(set)
assert(status.good == true and status.needsgood == true)
assert(status.needsnative == "dep" and root.needsnative.name == "native")
assert(status.deep == "dep" and root.deep.name == "native" and root.deep.reason == "build-type:make")
assert(status.oldprov == "dep" and root.oldprov.reason == "provided-version")
assert(status.missing == "dep" and root.missing.reason == "not-in-index")

-- sandbox: untrusted code cannot reach the system, and cannot hang us
local function fails(text) local rs, err = sandbox.load(text, "t"); assert(rs == nil, "should fail"); return err end
fails('os.execute("true")')
fails('io.open("/etc/passwd")')
fails('require("os")')
fails('loadfile("/etc/passwd")')
fails('dofile("/etc/passwd")')
assert(fails('while true do end'):find("too long"))
assert(sandbox.load('#!/usr/bin/env lua\npackage="x"\nversion="1"\n').package == "x")   -- leading #! line

print("filter ok")
