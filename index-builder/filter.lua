-- The pure-Lua filter (docs/pure-lua-filter.md). check() looks at ONE evaluated rockspec; closure() applies
-- rule 7 (dependencies must be accepted or provided by the firmware) over the whole set.
-- Every rejection has a short reason code so results can be counted and explained.

local V = require("vpm.version")

local M = {}

-- Libraries the firmware links in (rock name -> version). Keep in sync with vaporOS features/lua-libs.conf.
M.provided = { luafilesystem = "1.9.0", lpeg = "1.1.0", ["lua-cjson"] = "2.1.0" }

-- Packages that are only a stub on Lua 5.4: compat53 backports 5.3 features to 5.1/5.2 (its init.lua does nothing
-- on >= 5.3; the rock builds C modules only for those old versions). The runtime must preload an empty module.
M.provided.compat53 = "0.15.1"
M.stub = { compat53 = true }

local LUA = V.parse("5.4")

local function lua_ok(constraints)
  return V.satisfies(LUA, constraints)
end

-- every string reachable in a `modules` value (string | list | {sources=..., ...})
local function native_in(v)
  if type(v) == "string" then return not v:match("%.lua$") end
  if type(v) == "table" then
    for k, x in pairs(v) do
      if type(x) == "string" and (type(k) == "number" or k == "sources") then
        if not x:match("%.lua$") then return true end
      elseif type(x) == "table" and native_in(x) then
        return true
      end
    end
    -- {libraries=, defines=, incdirs=, libdirs=} without sources is still a native module description
    if v.libraries or v.defines or v.incdirs or v.libdirs then return true end
  end
  return false
end

-- Rule 11 (a TAG, not a rejection): code written for a host application (an editor, a game engine, a web
-- server) is pure Lua but needs that application's API, which vaporOS does not have. Detected from name,
-- labels and dependencies. The index records it as `host`; search/info show it, nothing is hidden by the builder.
local HOST = {
  { "nvim",      names = { "%.nvim$", "^nvim%-", "^neovim", "^telescope", "^lua%-language%-server" },
                 labels = { "neovim", "nvim" }, deps = { "^nvim", "^plenary" } },
  { "openresty", names = { "^lua%-resty%-", "^lapis", "^kong" }, labels = { "openresty", "nginx" },
                 deps = { "^lua%-resty%-", "^lapis$", "^openresty$" } },
  { "love",      names = { "^love", "%.love$" }, labels = { "love2d", "love" }, deps = { "^love" } },
  { "game",      names = {}, labels = { "roblox", "defold", "pico-8", "garrysmod", "minetest", "computercraft" }, deps = {} },
}

local function host_api(rs, deps)
  local labels = {}
  for _, l in ipairs((rs.description or {}).labels or {}) do labels[#labels + 1] = tostring(l):lower() end
  for _, h in ipairs(HOST) do
    for _, pat in ipairs(h.names) do if rs.package:lower():find(pat) then return h[1] end end
    for _, l in ipairs(labels) do for _, w in ipairs(h.labels) do if l:find(w, 1, true) then return h[1] end end end
    for _, d in ipairs(deps) do for _, pat in ipairs(h.deps) do if d.name:lower():find(pat) then return h[1] end end end
  end
end

-- returns ok, reason, info ; info = { deps = { {name=, constraints=}... } }
function M.check(rs)
  if type(rs.package) ~= "string" or type(rs.version) ~= "string" then return false, "no-package-or-version" end
  if type(rs.source) ~= "table" or type(rs.source.url) ~= "string" then return false, "no-source-url" end

  local build = rs.build or {}
  local btype = build.type or "builtin"
  if btype == "module" then btype = "builtin" end
  if btype ~= "builtin" and btype ~= "none" then return false, "build-type:" .. tostring(btype) end

  if rs.external_dependencies and next(rs.external_dependencies) then return false, "external-deps" end
  if build.libraries or build.defines or build.incdirs or build.libdirs then return false, "native-flags" end
  if build.install and build.install.lib and next(build.install.lib) then return false, "install-lib" end

  local function scan(b)
    if type(b) ~= "table" then return false end
    for _, v in pairs(b.modules or {}) do if native_in(v) then return true end end
    if b.libraries or b.defines or b.incdirs or b.libdirs then return true end
    return false
  end
  if scan(build) then return false, "native-source" end
  for _, p in pairs(build.platforms or {}) do if scan(p) then return false, "native-source" end end

  local deps = {}
  for _, s in ipairs(rs.dependencies or {}) do
    local d, err = V.parse_dep(s)
    if not d then return false, "bad-dependency" end
    if d.name == "lua" then
      if not lua_ok(d.constraints) then return false, "lua-version" end
    else
      deps[#deps + 1] = d
    end
  end
  return true, nil, { deps = deps, host = host_api(rs, deps) }
end

-- checked: name -> { ok, reason, deps }. Returns status, root:
--   status[name] = true | "reason"   (a dependency problem is "dep")
--   root[name]   = { name = <the rock that actually failed>, reason = <why> } for rejected rocks
function M.closure(checked)
  local status, root = {}, {}
  local function reject(name, reason, r)
    status[name] = reason; root[name] = r or { name = name, reason = reason }
    return reason
  end
  local function resolve(name, stack)
    if status[name] ~= nil then return status[name] end
    local c = checked[name]
    if not c then return "not-in-index" end
    if not c.ok then return reject(name, c.reason) end
    if stack[name] then return true end       -- cycle: assume ok, the others decide
    stack[name] = true
    for _, d in ipairs(c.deps) do
      local p = M.provided[d.name]
      if p then
        if not V.satisfies(p, d.constraints) then
          return reject(name, "dep", { name = d.name, reason = "provided-version" })
        end
      else
        local r = resolve(d.name, stack)
        if r ~= true then
          return reject(name, "dep", root[d.name] or { name = d.name, reason = tostring(r) })
        end
      end
    end
    stack[name] = nil
    status[name] = true
    return true
  end
  for name in pairs(checked) do resolve(name, {}) end
  return status, root
end

return M
