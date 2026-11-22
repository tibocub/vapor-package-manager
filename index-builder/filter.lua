-- The rockspec filter (docs/pure-lua-filter.md; since 2026-11-22 native code is classified, not rejected). check() looks at ONE evaluated rockspec; closure() applies
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

  -- Native code is not a reason to reject (2026-11-22): classify.lua says what building needs and the index records it.
  local native = require("classify").classify(rs)

  local deps = {}
  for _, s in ipairs(rs.dependencies or {}) do
    local d, err = V.parse_dep(s)
    if not d then return false, "bad-dependency" end
    if d.name == "lua" then
      -- not a rejection since 2026-11-22: the constraint is recorded (entry.lua) and shown; vlr's default dialect is 5.1, so "lua < 5.4" rocks are usable there
    else
      deps[#deps + 1] = d
    end
  end
  return true, nil, { deps = deps, host = host_api(rs, deps), native = native }
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
