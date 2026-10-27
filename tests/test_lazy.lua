-- Commands load only the code they need (docs/ram-budget.md): fewer modules means less heap on the RP2040.
package.path = "lib/?.lua;index-builder/?.lua;tests/lib/?.lua;" .. package.path
local fs, cli = require("vpm.fs"), require("vpm.cli")
local decode = require("json_decode")

local base = os.tmpname(); os.remove(base); assert(fs.mkdirp(base))
require("mirror").new(base .. "/mirror"){ lib1 = { versions = { ["1.0-1"] = { files = { ["lib1.lua"] = "return 1" } } } } }
local cfg = { libdir = base .. "/lib", appdir = base .. "/apps", bindir = base .. "/bin", index = "file://" .. base .. "/mirror/index/v1" }

local HEAVY = { "vpm.resolver", "vpm.version", "vpm.installer", "vpm.index", "vpm.transport", "vpm.hash" }
local function run(args)
  for _, m in ipairs(HEAVY) do package.loaded[m] = nil end
  package.loaded["vpm.maintain"] = nil
  local code = cli.main(args, { config = cfg, decode = decode, cwd = base .. "/proj", out = function() end, err = function() end })
  local loaded = {}
  for _, m in ipairs(HEAVY) do if package.loaded[m] then loaded[m] = true end end
  loaded.maintain = package.loaded["vpm.maintain"] and true
  return code, loaded
end
local function none(loaded, what) for m in pairs(loaded) do error(what .. " must not load " .. m) end end

for _, args in ipairs{ { "list", "-g" }, { "world" }, { "why", "lib1" } } do
  local _, loaded = run(args); none(loaded, args[1])
end
local _, loaded = run{ "remove", "-g", "nothing" }                   -- maintenance code only
assert(loaded.maintain and not loaded["vpm.resolver"] and not loaded["vpm.installer"] and not loaded["vpm.index"]
  and not loaded["vpm.transport"] and not loaded["vpm.hash"], "remove loaded too much")
_, loaded = run{ "check" }
assert(loaded.maintain and not loaded["vpm.resolver"] and not loaded["vpm.installer"] and not loaded["vpm.index"])
_, loaded = run{ "info", "lib1" }                                    -- index only
assert(loaded["vpm.index"] and not loaded["vpm.installer"] and not loaded["vpm.resolver"])
local code
code, loaded = run{ "install", "-g", "lib1" }
assert(code == 0 and fs.exists(base .. "/lib/lib1.lua"))
assert(loaded["vpm.installer"] and not loaded["vpm.resolver"] and not loaded["vpm.version"], "resolver must be released before downloading")

fs.rmtree(base)
print("lazy ok")
