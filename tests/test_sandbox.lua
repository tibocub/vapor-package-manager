package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local sandbox = require("sandbox")
local function eval(text) return sandbox.load(text, "t") end

local r = assert(eval('package = {name = "x", version = "1.0-1"}; dependencies = {"lua >= 5.1"}'))
assert(r.package.name == "x" and r.dependencies[1] == "lua >= 5.1")

-- no way out
assert(not eval('x = io.open("/etc/passwd")'))
assert(not eval('x = os.execute("true")'))
assert(not eval('x = require("os")'))
assert(not eval('x = load("return 1")()'))
assert(not eval('x = dofile("/etc/passwd")'))
assert(not eval('x = debug.getinfo(1)'))
assert(not eval('x = getmetatable("")'))
assert(not eval('x = setmetatable({}, {})'))
assert(not eval('x = rawset(_G, "a", 1)'))

-- a rockspec cannot change the builtins other rockspecs (or the builder) see
assert(eval('string.find = function() return 1 end; string.rep = nil; table.concat = nil; math.floor = nil'))
assert(string.find("abc", "b") == 2 and string.rep("a", 3) == "aaa" and table.concat({"a", "b"}) == "ab" and math.floor(1.5) == 1, "builtins intact")
assert(eval('x = ("a"):find("a")').x == 1, "other rockspecs still get the real thing")

-- resource bombs fail cleanly instead of eating the machine
assert(not eval('x = string.rep("x", 1e9)'))
assert(not eval('x = ("x"):rep(2^30)'))
assert(not eval('x = string.rep("ab", 1e8, ",")'))
assert(not eval('while true do end'))
assert(not eval('x = string.find(string.rep("a", 400) .. string.rep("a", 400), ".-.-.-.-.-.-.-b")'))
assert(not eval('local t = {}; for i = 1, 1e7 do t[i] = i end'), "the step limit stops long loops")
print("sandbox ok")
