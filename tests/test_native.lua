package.path = "lib/?.lua;tests/lib/?.lua;" .. package.path
local fs, native, profile = require("vpm.fs"), require("vpm.native"), require("vpm.profile")

-- profile: what the machine can do, from injected facts
local function detect(caps, have, cc)
  return profile.detect{ vapor = { caps = caps, platform = "linux", dialect = "5.1" }, run = function(cmd) for t in pairs(have) do if cmd:find("command -v " .. t .. " ", 1, true) then return true end end return false end,
    getenv = function(n) if n == "CC" then return cc end end }
end
local p = detect({ exec = true, dlopen = true }, { cc = 1, tar = 1, unzip = 1 })
assert(p.can_build_c and p.cc == "cc" and #p.missing == 0)
p = detect({ exec = true, dlopen = true }, { tar = 1, unzip = 1 })
assert(not p.can_build_c and p.missing[1] == "a C compiler")
p = detect({ exec = true, dlopen = false }, { cc = 1, tar = 1, unzip = 1 })
assert(not p.can_build_c and p.missing[1]:find("dlopen"))
p = detect({ exec = false, dlopen = false }, {})
assert(not p.can_build_c and p.missing[1]:find("run programs"))
p = detect({ exec = true, dlopen = true }, { clang = 1, tar = 1, unzip = 1 })
assert(p.cc == "clang", "falls back to other compilers")
p = detect({ exec = true, dlopen = true }, { ["/opt/mycc"] = 1, tar = 1, unzip = 1 }, "/opt/mycc")
assert(p.cc == "/opt/mycc", "CC wins")
p = detect({ exec = true, dlopen = true }, { cc = 1, tar = 1, unzip = 1 }, "x; rm -rf /")
assert(p.cc == "cc", "CC with shell characters is ignored")
local good = detect({ exec = true, dlopen = true }, { cc = 1, tar = 1, unzip = 1 })
local nocc = detect({ exec = true, dlopen = true }, { tar = 1, unzip = 1 })
assert(profile.can_install(good, nil) and profile.can_install(good, "c") and not profile.can_install(nocc, "c") and not profile.can_install(good, "other") and not profile.can_install(good, "build"))

-- quoting and plan validation: the plan comes from the network
assert(native.shq("a b") == "'a b'" and native.shq("it's") == "'it'\\''s'")
local function plan(m) return { modules = { m } } end
assert(native.validate(plan{ name = "a.b", sources = { "src/a.c" }, defines = { 'V="1"' }, libraries = { "m", "z" } }))
local function bad(m, what) local ok, err = native.validate(plan(m)); assert(not ok and err:find(what, 1, true), tostring(err)) end
bad({ name = "a b", sources = { "a.c" } }, "module name")
bad({ name = "a;rm", sources = { "a.c" } }, "module name")
bad({ name = "../a", sources = { "a.c" } }, "module name")
bad({ name = "a", sources = { "../a.c" } }, "bad source")
bad({ name = "a", sources = { "/etc/a.c" } }, "bad source")
bad({ name = "a", sources = { "a.sh" } }, "bad source")
bad({ name = "a", sources = {} }, "no sources")
bad({ name = "a", sources = { "a.c" }, libraries = { "m; id" } }, "bad library")
bad({ name = "a", sources = { "a.c" }, defines = { "X\n" } }, "bad defines")
assert(not native.validate({}) and not native.validate({ modules = {} }))

-- external libraries: $(NAME_INCDIR) found under the usual prefixes
local present = { ["/opt/x/include/zlib.h"] = true, ["/opt/x/lib/libz.so"] = true }
local vars, missing = native.locate_external({ external = { ZLIB = { header = "zlib.h", library = "z" } } }, { "/usr", "/opt/x" }, function(p) return present[p] end)
assert(vars.ZLIB_INCDIR == "/opt/x/include" and vars.ZLIB_LIBDIR == "/opt/x/lib" and #missing == 0)
vars, missing = native.locate_external({ external = { SSL = { header = "openssl/ssl.h", library = "ssl" } } }, { "/usr" }, function() return false end)
assert(#missing == 2 and missing[1]:find("SSL"), "missing libraries are named")

-- the command line
local cmd = native.command({ cc = "cc", platform = "linux" }, "/h", { name = "m", sources = { "a.c", "b d.c" }, defines = { 'PKG="x y"' }, incdirs = { "inc", "$(ZLIB_INCDIR)" },
  libdirs = { "$(ZLIB_LIBDIR)" }, libraries = { "z" } }, "/src", "/out/m.so", { ZLIB_INCDIR = "/opt/x/include", ZLIB_LIBDIR = "/opt/x/lib" })
assert(cmd:find("'cc' -O2 -shared -fPIC -I'/h'", 1, true) and cmd:find("-I'/src/inc'", 1, true) and cmd:find("-I'/opt/x/include'", 1, true) and cmd:find("-D'PKG=\"x y\"'", 1, true)
  and cmd:find("'/src/b d.c'", 1, true) and cmd:find("-L'/opt/x/lib'", 1, true) and cmd:find("-l'z'", 1, true) and cmd:find("-o '/out/m.so'", 1, true), cmd)
assert(native.command({ cc = "cc", platform = "macos" }, "/h", { name = "m", sources = { "a.c" } }, "/s", "/o.so"):find("-bundle -undefined dynamic_lookup", 1, true))

-- a real build, if this runtime can load what it builds
if vapor.caps.dlopen and good.can_build_c and nocc then
  local live = profile.detect()
  if live.can_build_c then
    local base = os.tmpname(); os.remove(base); assert(fs.mkdirp(base .. "/src/sub")); assert(fs.mkdirp(base .. "/dest"))
    fs.write(base .. "/src/sub/add.c", '#include "lua.h"\n#include "lauxlib.h"\nstatic int add(lua_State *L){ lua_pushinteger(L, luaL_checkinteger(L,1) + luaL_checkinteger(L,2) + OFFSET); return 1; }\nint luaopen_vpmnative_add(lua_State *L){ lua_newtable(L); lua_pushcfunction(L, add); lua_setfield(L, -2, "add"); return 1; }\n')
    local built, err = native.build(live, { modules = { { name = "vpmnative.add", sources = { "sub/add.c" }, defines = { "OFFSET=100" } } } }, base .. "/src", base .. "/dest")
    assert(built and built[1] == "vpmnative/add.so", err)
    package.cpath = base .. "/dest/?.so;" .. package.cpath
    assert(require("vpmnative.add").add(1, 2) == 103, "the built module loads and runs")
    assert(not fs.exists(base .. "/dest/.vpm-build-headers"), "build scratch removed")

    fs.write(base .. "/src/sub/broken.c", "this is not C;\n")
    local b2, e2 = native.build(live, { modules = { { name = "vpmnative.ok2", sources = { "sub/add.c" }, defines = { "OFFSET=0" } }, { name = "vpmnative.broken", sources = { "sub/broken.c" } } } }, base .. "/src", base .. "/dest")
    assert(b2 == nil and e2:find("building vpmnative.broken failed", 1, true), tostring(e2))
    assert(not fs.exists(base .. "/dest/vpmnative/ok2.so"), "a failed build leaves nothing behind")
    fs.rmtree(base)
  end
end

-- unpacking: a plain tar.gz with one top directory, and a zip holding a loose tree (like a git rock's src.rock)
if good.tools.tar and os.execute("command -v tar >/dev/null 2>&1") == 0 then
  local base = os.tmpname(); os.remove(base); assert(fs.mkdirp(base .. "/pkg-1.0/src"))
  fs.write(base .. "/pkg-1.0/src/a.c", "int a;")
  assert(os.execute("cd " .. native.shq(base) .. " && tar -czf pkg.tar.gz pkg-1.0") == 0)
  local root, err = native.unpack({ tools = { tar = true } }, base .. "/pkg.tar.gz", base .. "/w1")
  assert(root and fs.read(root .. "/src/a.c") == "int a;", err)
  if os.execute("command -v zip >/dev/null 2>&1") == 0 and os.execute("command -v unzip >/dev/null 2>&1") == 0 then
    fs.write(base .. "/x.rockspec", "package='x'")
    assert(os.execute("cd " .. native.shq(base) .. " && zip -qr x.src.rock x.rockspec pkg-1.0") == 0)
    root, err = native.unpack({ tools = { tar = true, unzip = true } }, base .. "/x.src.rock", base .. "/w2")
    assert(root and fs.read(root .. "/src/a.c") == "int a;", err)
    assert(native.unpack({ tools = {} }, base .. "/x.src.rock", base .. "/w3") == nil, "no unzip: refused")
  end
  fs.rmtree(base)
end
print("native ok")
