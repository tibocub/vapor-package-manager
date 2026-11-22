package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local classify = require("classify").classify
local sandbox = require("sandbox")
local function spec(body) return assert(sandbox.load('package="demo"\nversion="1-1"\nsource={url="x"}\n' .. body, "t")) end
local function c(body, tree) return classify(spec(body), tree) end

assert(c("").native == false and c('build={type="builtin",modules={a="a.lua"}}').native == false and c('build={type="none"}').native == false)

local r = c('build={modules={demo={sources={"demo.c"}}}}')
assert(r.native == "c" and r.langs[1] == "c" and #r.langs == 1)
assert(c('build={modules={demo="src/demo.c"}}').native == "c")
assert(c('build={platforms={unix={modules={demo="demo.c"}}}}').native == "c")
assert(c('build={modules={demo={sources={"a.lua","b.cpp"}}}}').native == "other" and c('build={modules={demo={sources={"a.cxx"}}}}').langs[1] == "c++")
assert(c('build={modules={demo={sources={"a.c","b.cc"}}}}').native == "other", "C + C++ is not C only")
r = c('build={modules={demo={sources={"a.c","b.S"}}}}')
assert(r.native == "other" and r.langs[1] == "asm" and r.langs[2] == "c")

r = c('external_dependencies={OPENSSL={header="openssl/ssl.h"}}')
assert(r.native == "other" and r.unknown_language and r.external[1] == "OPENSSL", "external deps without sources: native, language unknown")
r = c('build={modules={a="a.c"}}\nexternal_dependencies={ZLIB={header="zlib.h"},OPENSSL={header="o.h"}}')
assert(r.native == "c" and r.external[1] == "OPENSSL" and r.external[2] == "ZLIB", "C with system libraries stays C; names sorted")
assert(c('build={libraries={"m"}}').native == "other", "libraries without sources: native, language unknown")
r = c('build={install={lib={demo="demo.so"}}}')
assert(r.native == "other" and r.prebuilt, "prebuilt library")

-- opaque build systems: the tree decides
r = c('build={type="make"}')
assert(r.native == "other" and r.unknown_language and r.build == "make", "make without a tree: native, language unknown")
r = c('build={modules={demo={sources={"a.c"},defines={"V=1"},incdirs={"lua-compat-5.3","inc.d"},libdirs={"x.y"}}}}')
assert(r.native == "c" and #r.langs == 1, "incdirs/defines/libdirs are not source files")
r = c('build={type="make"}', { "Makefile", "lua/x.lua", "README.md" })
assert(r.native == "build", "make but nothing to compile")
r = c('build={type="make"}', { "Makefile", "src/a.c", "src/a.h", "lua/x.lua", "README.md" })
assert(r.native == "c" and not r.unknown_language, "make with only C sources is C")
r = c('build={type="cmake"}', { "CMakeLists.txt", "src/a.c", "src/b.cpp" })
assert(r.native == "other" and r.langs[1] == "c" and r.langs[2] == "c++")
assert(c('build={type="rust-mlua"}').langs[1] == "rust" and c('build={type="rust-mlua"}').native == "other")
assert(c('build={type="command", build_command="x"}', { "a.lua" }).native == "build", "command with only Lua in the tree: a build step, no compiled code")
assert(c('build={type="command", build_command="x"}').native == "other" and c('build={type="command", build_command="x"}').unknown_language, "command without a tree: unknown")
r = c('build_dependencies={"luarocks-build-luke >= 0.3"}\nbuild={type="luke"}', { "a.c" })
assert(r.native == "c" and r.build_deps[1] == "luarocks-build-luke >= 0.3" and r.build == "luke", "a build backend is recorded")
print("classify ok")
