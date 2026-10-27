package.path = "lib/?.lua;" .. package.path
local R = require("vpm.resolver")

-- fake index: pkg -> version -> deps (strings)
local function mk(t)
  return function(name)
    local p = t[name]; if not p then return nil end
    local vs = {}
    for v, deps in pairs(p) do vs[v] = { deps = deps, size = 1000 } end
    return { versions = vs }
  end
end
local function find(plan, name) for _, a in ipairs(plan.actions) do if a.name == name then return a end end end
local function try(o) local p, e = R.resolve(o); return p, e end
local function summary(plan)
  local t = {}
  for _, a in ipairs(plan.actions) do t[#t + 1] = ("%s %s %s %s"):format(a.action, a.name, a.version, a.scope) end
  return table.concat(t, "; ")
end

local index = mk{
  argparse   = { ["0.7.1-1"] = { "penlight < 1.14" }, ["0.6.0-1"] = {} },
  penlight   = { ["1.13.1-1"] = { "luafilesystem" }, ["1.14.0-1"] = { "luafilesystem" }, ["scm-1"] = {} },
  ["lua-term"] = { ["0.8-1"] = {} },
  notes      = { ["0.3.1-1"] = { "lpeg >= 1.0", "penlight >= 1.13", "lua-term" } },
  strict     = { ["1.0-1"] = { "penlight < 1.14" } },
  old        = { ["1.0-1"] = { "lpeg < 1.0" } },
  a = { ["1-1"] = { "b" } }, b = { ["1-1"] = { "a" } },
}
local provided = { lpeg = "1.1.0", luafilesystem = "1.9.0" }
local base = { scope = "local", provided = provided, installed = {}, index = index }
local function with(extra) local o = {} for k, v in pairs(base) do o[k] = v end for k, v in pairs(extra) do o[k] = v end return o end

-- 1. dependencies first, provided libraries reused, highest non-scm version, auto => new deps global
local p = assert(try(with{ requests = { { name = "notes" } } }))
local parts = {}
for part in summary(p):gmatch("[^;]+") do parts[#parts + 1] = part:match("^%s*(.-)%s*$") end
table.sort(parts)
assert(table.concat(parts, "; ") == "install lua-term 0.8-1 global; install notes 0.3.1-1 local; install penlight 1.14.0-1 global; "
  .. "reuse lpeg 1.1.0 firmware; reuse luafilesystem 1.9.0 firmware", summary(p))
assert(p.actions[#p.actions].name == "notes", "dependencies come before the package that needs them")
assert(p.download == 3000)

-- 2. already installed versions are preferred over the index
p = assert(try(with{ requests = { { name = "penlight" } },
  installed = { global = { penlight = { version = "1.13.1-1", deps = {} } } } }))
assert(find(p, "penlight").action == "reuse" and find(p, "penlight").version == "1.13.1-1")

-- 3. worked example: needing 1.14 while global 1.13 is used by argparse (>= 1.10): shadow locally
local inst = { global = { penlight = { version = "1.13.1-1", deps = {} },
                          argparse = { version = "0.7.1-1", deps = { penlight = ">= 1.10" } } } }
p = assert(try(with{ requests = { { name = "argparse" }, { name = "penlight", constraint = ">= 1.14" } }, installed = inst }))
local pl = find(p, "penlight")
assert(pl.action == "install" and pl.scope == "local" and pl.shadows == "1.13.1-1", summary(p))
assert(find(p, "argparse").action == "reuse")

-- 4. closure rule: a global package rejects the shadow => it gets a private older version
inst.global.argparse.deps = { penlight = "< 1.14" }
p = assert(try(with{ requests = { { name = "argparse" }, { name = "penlight", constraint = ">= 1.14" } }, installed = inst }))
assert(find(p, "penlight").version == "1.14.0-1" and find(p, "argparse").action == "install"
  and find(p, "argparse").version == "0.6.0-1" and find(p, "argparse").scope == "local", summary(p))

-- 5. conflict between two requirements: error names the chain
local plan, err = try(with{ requests = { { name = "strict" }, { name = "penlight", constraint = ">= 1.14" } } })
assert(not plan and err:find("strict") and err:find("1.14"), tostring(err))

-- 6. firmware version too old for a dependency
plan, err = try(with{ requests = { { name = "old" } } })
assert(not plan and err:find("firmware provides lpeg 1.1.0") or err:find("lpeg"), tostring(err))

-- 7. -g puts everything global and a global package may not use local ones
p = assert(try(with{ scope = "global", requests = { { name = "notes" } } }))
for _, a in ipairs(p.actions) do assert(a.scope == "global" or a.scope == "firmware", summary(p)) end

-- 8. --deps=local keeps new dependencies local
p = assert(try(with{ deps = "local", requests = { { name = "notes" } } }))
assert(find(p, "penlight").scope == "local" and find(p, "lua-term").scope == "local")

-- 9. replacing a global version reports what it breaks (and never silently: action carries `replaces`)
inst = { global = { penlight = { version = "1.13.1-1", deps = {} }, strict = { version = "1.0-1", deps = { penlight = "< 1.14" } } } }
p = assert(try(with{ scope = "global", requests = { { name = "penlight", constraint = ">= 1.14" } }, installed = inst }))
assert(find(p, "penlight").replaces == "1.13.1-1" and #p.breaks == 1 and p.breaks[1].by == "strict")

-- 10. unreleased versions only when named explicitly; unknown package; cycles terminate
plan, err = try(with{ requests = { { name = "penlight", constraint = "== scm-1" } } })
assert(plan and find(plan, "penlight").version == "scm-1")
plan, err = try(with{ requests = { { name = "nope" } } })
assert(not plan and err:find("not in the index"), tostring(err))
assert(try(with{ requests = { { name = "a" } } }))

print("resolver ok")
