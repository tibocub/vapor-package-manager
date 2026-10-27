package.path = "lib/?.lua;index-builder/?.lua;tests/lib/?.lua;" .. package.path
local fs, cli = require("vpm.fs"), require("vpm.cli")
local decode = require("json_decode")

local base = os.tmpname(); os.remove(base); assert(fs.mkdirp(base))
local mirror, sys, proj = base .. "/mirror", base .. "/sys", base .. "/proj"
assert(fs.mkdirp(proj))
local publish = require("mirror").new(mirror)
publish{
  ansicolors = { versions = { ["1.0-1"] = { files = { ["ansicolors.lua"] = "return 'colors'" }, summary = "ANSI colors" } } },
  lpeglike = { versions = { ["1.0-1"] = { files = { ["lpeglike.lua"] = "return 'l'" } } } },
  mathx = { versions = { ["1.0-1"] = { files = { ["mathx.lua"] = "return 1" }, deps = { "lpeglike >= 1.0" } } } },
  pk = { versions = { ["1.2-1"] = { files = { ["pk.lua"] = "return '1.2'" } }, ["1.3-1"] = { files = { ["pk.lua"] = "return '1.3'" } } } },
}

local config = { libdir = sys .. "/lib", appdir = sys .. "/apps", bindir = sys .. "/bin", index = "file://" .. mirror .. "/index/v1" }
local function vpm(args, answers, cwd)
  local out, err = {}, {}
  local code = cli.main(args, { config = config, decode = decode, cwd = cwd or proj,
    out = function(s) out[#out + 1] = s end, err = function(s) err[#err + 1] = s end,
    read = function() if answers == nil then return nil end return table.remove(answers, 1) end,
    now = function() return 0 end })
  return code, table.concat(out), table.concat(err)
end
local function has(s, pat) return s:find(pat, 1, true) ~= nil end

-- usage and parsing
assert(select(1, vpm({})) == 2)
assert(select(1, vpm({ "frobnicate" })) == 2)
assert(select(1, vpm({ "install", "--bogus" })) == 2)
assert(select(1, vpm({ "install", "--deps=sideways" })) == 2)

-- 1. a single package without dependencies installs without asking (no terminal: answers = nil)
local code, out = vpm({ "i", "-g", "ansicolors" })
assert(code == 0 and has(out, "install") and fs.read(sys .. "/lib/ansicolors.lua") == "return 'colors'", out)

-- 2. dependencies to fetch => it asks; no terminal refuses; "n" aborts; -y goes
code, out, err = vpm({ "install", "-g", "mathx" })
assert(code == 1 and has(err, "no terminal") and not fs.exists(sys .. "/lib/mathx.lua"))
code, out = vpm({ "install", "-g", "mathx" }, { "n" })
assert(code == 1 and has(out, "Continue? [Y/n]") and has(out, "aborted") and not fs.exists(sys .. "/lib/mathx.lua"))
code = vpm({ "install", "-g", "-n", "mathx" })
assert(code == 0 and not fs.exists(sys .. "/lib/mathx.lua"))             -- dry run
code, out = vpm({ "install", "-g", "mathx" }, { "" })                    -- Enter = yes
assert(code == 0 and fs.exists(sys .. "/lib/mathx.lua") and fs.exists(sys .. "/lib/lpeglike.lua"), out)

-- 3. list, world, why
code, out = vpm({ "ls", "-g" })
assert(has(out, "mathx") and has(out, "world") and has(out, "lpeglike") and has(out, "dep"))
fs.write(sys .. "/lib/handmade.lua", "return 1")
code, out = vpm({ "list", "-g" })
assert(has(out, "handmade.lua") and has(out, "(unmanaged)"))
code, out = vpm({ "world" })
assert(has(out, "mathx") and has(out, "ansicolors") and not has(out, "lpeglike"))
code, out = vpm({ "why", "lpeglike" })
assert(has(out, "mathx") and has(out, "needs lpeglike >= 1.0"), out)
code, out = vpm({ "why", "ansicolors" })
assert(has(out, "nothing installed depends on ansicolors"))

-- 4. remove refuses while needed
code, out, err = vpm({ "remove", "-g", "lpeglike" })
assert(code == 3 and has(err, "needed by mathx"))
code = vpm({ "rm", "-g", "mathx" }); assert(code == 0 and not fs.exists(sys .. "/lib/mathx.lua"))
assert(select(1, vpm({ "remove", "-g", "nope" })) == 1)

-- 5. name@1.2 is the LuaRocks prefix match: 1.2.x, not 1.3
code = vpm({ "install", "-g", "pk@1.2" }); assert(code == 0 and fs.read(sys .. "/lib/pk.lua") == "return '1.2'")
vpm({ "remove", "-g", "pk" })
code = vpm({ "install", "-g", "pk" }); assert(fs.read(sys .. "/lib/pk.lua") == "return '1.3'")
vpm({ "remove", "-g", "pk" })

-- 6. upgrade: nothing newer, then a newer one appears
vpm({ "install", "-g", "-y", "pk@1.2" })
code, out = vpm({ "upgrade", "-g", "-y" })
assert(code == 0 and has(out, "up to date") or has(out, "upgrade"), out)       -- world constraint ~> 1.2 keeps 1.2
publish{ pk = { versions = { ["1.2-2"] = { files = { ["pk.lua"] = "return '1.2-2'" } }, ["1.2-1"] = { files = { ["pk.lua"] = "return '1.2'" } } } } }
code, out = vpm({ "upgrade", "-g" }, { "y" })
assert(code == 0 and has(out, "1.2-1 -> 1.2-2") and fs.read(sys .. "/lib/pk.lua") == "return '1.2-2'", out)
code, out = vpm({ "upgrade", "-g", "pk" }); assert(has(out, "up to date"))

-- 7. a project: vpm.lua deps, local scope, lock file, registered, shared dependency
fs.write(proj .. "/vpm.lua", 'return { name = "demo", version = "0.1.0", deps = { ansicolors = ">= 1.0" } }')
code, out = vpm({ "install" })
assert(code == 0 and has(out, "reuse") and has(out, "global"), out)             -- the global copy is reused
assert(fs.exists(proj .. "/vpm-lock.lua") and has(fs.read(proj .. "/vpm-lock.lua"), "ansicolors"))
assert(not fs.exists(proj .. "/lua_modules/ansicolors.lua"))
assert(require("vpm.state").open(sys .. "/lib"):projects()[proj])
code, out = vpm({ "why", "ansicolors" }, nil, base)                              -- seen from elsewhere via registration
assert(has(out, "ansicolors 1.0-1 is installed"))
code, out = vpm({ "install", "mathx" })                                          -- named package only: reuses global lpeglike, no prompt
assert(code == 0 and fs.exists(proj .. "/lua_modules/mathx.lua") and not fs.exists(proj .. "/lua_modules/lpeglike.lua"), out)
vpm({ "remove", "mathx" }); vpm({ "remove", "-g", "lpeglike" })
code, out, err = vpm({ "install", "mathx" })                                     -- now a dependency must be fetched, globally
assert(code == 1 and has(err, "no terminal") and not fs.exists(proj .. "/lua_modules/mathx.lua"))
code = vpm({ "install", "-y", "--deps=local", "mathx" })
assert(code == 0 and fs.exists(proj .. "/lua_modules/mathx.lua") and fs.exists(proj .. "/lua_modules/lpeglike.lua"))

-- 8. info
code, out = vpm({ "info", "ansicolors" })
assert(code == 0 and has(out, "ANSI colors") and has(out, "installed: 1.0-1 (global)"))
code, out = vpm({ "info", "nothing-like-it" }); assert(code == 1 and has(out, "not in the index"))

-- 9. check finds damage, --repair undoes a crashed run
fs.write(sys .. "/lib/ansicolors.lua", "tampered")
code, out = vpm({ "check" }); assert(code == 1 and has(out, "modified ansicolors.lua"))
fs.write(sys .. "/lib/ansicolors.lua", "return 'colors'")
fs.write(sys .. "/lib/.vpm/lock", "ghost\t" .. sys .. "/lib/ghost.lua\n"); fs.write(sys .. "/lib/ghost.lua", "partial")
code, out = vpm({ "check", "--repair" })
assert(has(out, "removed 1 leftover") and not fs.exists(sys .. "/lib/ghost.lua") and not fs.exists(sys .. "/lib/.vpm/lock"), out)
assert(select(1, vpm({ "check" })) == 0)

-- 10. init
local empty = base .. "/empty"; fs.mkdirp(empty)
code = vpm({ "init", "-y" }, nil, empty)
assert(code == 0 and has(fs.read(empty .. "/vpm.lua"), 'name = "empty"'))
assert(select(1, vpm({ "init", "-y" }, nil, empty)) == 1)

-- 11. unresolvable and unknown packages exit 3
code, out, err = vpm({ "install", "-g", "doesnotexist" }); assert(code == 3 and has(err, "not in the index"))

fs.rmtree(base)
print("cli ok")
