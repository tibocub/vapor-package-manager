package.path = "lib/?.lua;" .. package.path
local V = require("vpm.version")
local function eq(a, b, msg) assert(a == b, (msg or "") .. ": got " .. tostring(a) .. ", want " .. tostring(b)) end

-- ordering
assert(V.less("1.2", "1.10")); assert(V.less("1.0-1", "1.0-2")); assert(not V.less("1.0-2", "1.0-1"))
assert(V.less("1.0", "1.0.1")); assert(V.less("2.0alpha", "2.0beta")); assert(V.less("2.0rc1", "2.0"))
assert(V.less("9.9", "scm-1")); assert(V.less("1.0", "dev-1"))
-- revision is ignored when only one side has one
assert(V.parse("1.0-3") == V.parse("1.0"))

-- constraints
local function ok(v, c) return V.satisfies(v, assert(V.parse_constraints(c))) end
assert(ok("1.5", ">= 1.0, < 2")); assert(not ok("2.0", ">= 1.0, < 2"))
assert(ok("1.2.3", "~> 1.2")); assert(ok("1.2", "~> 1.2")); assert(not ok("1.3", "~> 1.2"))  -- LuaRocks prefix match
assert(ok("5.4", "~> 5.1") == false)   -- 5.4 does not start with 5.1
assert(ok("5.4", ">= 5.1")); assert(ok("1.0", "1.0")); assert(ok("1.0", "== 1.0")); assert(not ok("1.1", "!= 1.1"))

-- dependency strings
local d = assert(V.parse_dep("lpeg >= 0.12, < 2.0")); eq(d.name, "lpeg"); eq(#d.constraints, 2)
d = assert(V.parse_dep("penlight")); eq(#d.constraints, 0)
d = assert(V.parse_dep("lua >= 5.1")); eq(d.name, "lua")
assert(not V.parse_dep("lpeg >>> 1"))

-- parity with the installed LuaRocks, when present
local okr, R = pcall(require, "luarocks.core.vers")
if okr then
  local vs = { "1.0", "1.0-1", "1.0-2", "1.2.3", "1.10", "2.0beta", "2.0rc1", "2.0", "scm-1", "dev-1", "0.5", "1.0.0" }
  local n = 0
  for _, a in ipairs(vs) do for _, b in ipairs(vs) do
    eq(V.less(a, b), R.parse_version(a) < R.parse_version(b), a .. " < " .. b); n = n + 1
  end end
  for _, v in ipairs(vs) do for _, c in ipairs({ "~> 1.0", "~> 1.2", ">= 1.0, < 2", "== 1.0-1", "~= 1.0" }) do
    local cs = assert(V.parse_constraints(c))
    local rc = {} for _, x in ipairs(cs) do rc[#rc + 1] = { op = x.op, version = x.version.string } end
    eq(V.satisfies(v, cs), R.match_constraints(R.parse_version(v), rc), v .. " " .. c); n = n + 1
  end end
  print("parity with luarocks: " .. n .. " comparisons")
end
print("version ok")
