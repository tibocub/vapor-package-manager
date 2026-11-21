package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local sandbox, pkg, json = require("sandbox"), require("package_analysis"), require("json")

local base = os.tmpname(); os.remove(base); assert(os.execute("mkdir -p " .. base))
local n = 0
local function tree(files, rockspec)
  n = n + 1
  local root = base .. "/t" .. n
  for path, text in pairs(files) do
    os.execute("mkdir -p '" .. root .. "/" .. (path:match("^(.*)/[^/]*$") or "") .. "'")
    local f = assert(io.open(root .. "/" .. path, "wb")); f:write(text); f:close()
  end
  local rs = assert(sandbox.load('package="d"\nversion="1"\nsource={url="u"}\n' .. rockspec, "t"))
  return rs, root
end
local origin = { type = "git" }
local function ok(files, rockspec)
  local rs, root = tree(files, rockspec); local e, why = pkg.analyze(rs, root, origin); assert(e, why); return e
end
local function bad(files, rockspec, reason)
  local rs, root = tree(files, rockspec); local e, why = pkg.analyze(rs, root, origin)
  assert(not e and why:find(reason, 1, true) == 1, "wanted " .. reason .. ", got " .. tostring(why))
end

-- explicit modules; luarocks destination rules
local e = ok({ ["src/a.lua"] = "return 1", ["src/b/init.lua"] = "return 2", ["x/c.lua"] = "return 3" },
  'build={modules={a="src/a.lua", b="src/b/init.lua", ["p.q"]="x/c.lua"}}')
assert(e.files["a.lua"] and e.files["b/init.lua"] and e.files["p/q.lua"], "destinations")
assert(#e.files["a.lua"].sha256 == 64 and e.files["a.lua"].size == 8)
assert(table.concat(e.modules, ",") == "a,b,p.q")

-- auto-detection when `build.modules` is absent: src/ prefix, skips spec/, no C
e = ok({ ["src/m.lua"] = "return 1", ["src/sub/n.lua"] = "return 2", ["spec/m_spec.lua"] = "x" }, "")
assert(e.files["m.lua"] and e.files["sub/n.lua"] and not e.files["spec/m_spec.lua"], "autodetect")
bad({ ["src/m.lua"] = "return 1", ["src/m.c"] = "int x;" }, "", "native-source")

-- bin scripts, shebang lines, require() scanning
e = ok({ ["bin/t"] = "#!/usr/bin/env lua\nlocal s = require('socket')\nprint(1)", ["l.lua"] = "local x = require 'lpeg'; local y = require('l')" },
  'build={modules={l="l.lua"}, install={bin={tool="bin/t"}}}')
assert(e.bin.tool == "bin/tool")
local req = table.concat(e.requires, ",")
assert(req:find("socket") and req:find("lpeg") and not req:find("string"), req)

-- rejections
bad({ ["a.lua"] = "return (" }, 'build={modules={a="a.lua"}}', "syntax-5.4")
bad({ ["a.lua"] = "return 1" }, 'build={modules={a="gone.lua"}}', "missing-file")
bad({}, 'build={modules={a="../../etc/x.lua"}}', "unsafe-path")
bad({ ["a.so"] = "x" }, 'build={modules={a="a.so"}}', "native-source")
bad({ ["a.lua"] = ("x"):rep(520000) }, 'build={modules={a="a.lua"}}', "file-too-large")

-- json: sorted keys, escapes, arrays
assert(json.encode({ b = 1, a = { "x", "y\n" } }):gsub("%s", "") == '{"a":["x","y\\n"],"b":1}')
os.execute("rm -rf '" .. base .. "'")
print("package ok")
