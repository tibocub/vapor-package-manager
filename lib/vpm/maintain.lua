-- Everything that is not downloading: the scope state, removing packages, verifying files and undoing a crashed
-- run. Separate from installer.lua so `remove`, `check` and `repair` do not load the install code (and the other
-- way round: installing loads only the few helpers it shares). Methods are shared by both through inheritance.
local fs = require("vpm.fs")
local State = require("vpm.state")
local M = {}
local I = {}
I.__index = I
M.class = I

-- cfg = { libdir, appdir, bindir, local_root, ... }
function M.new(o)
  return setmetatable({ cfg = o.cfg, now = o.now or os.time, states = {} }, I)
end

function I:state(scope)
  if not self.states[scope] then
    local root = scope == "global" and self.cfg.libdir or self.cfg.local_root
    if not root then return nil, "no " .. scope .. " root configured" end
    self.states[scope] = State.open(root)
  end
  return self.states[scope]
end

function I:base_dir(st, kind, name)
  if kind == "app" then return self.cfg.appdir .. "/" .. name end
  return st.root
end

function I.owners(st)
  local o = {}
  for _, n in ipairs(st:names()) do
    local r = st:get(n)
    if r and r.base ~= "app" then for f in pairs(r.files or {}) do o[f] = n end end
  end
  return o
end

function I:remove_files(st, rec)
  local base = self:base_dir(st, rec.kind, rec.name)
  for f in pairs(rec.files or {}) do
    fs.remove(base .. "/" .. f)
    fs.prune((base .. "/" .. f):match("^(.*)/[^/]*$"), rec.kind == "app" and base or st.root)
  end
  for _, p in pairs(rec.launchers or {}) do fs.remove(p) end
  if rec.kind == "app" then fs.prune(base, self.cfg.appdir) end
end

-- Undo a crashed run: files listed in the journal that no complete record owns are removed.
function I:repair(scope)
  local st, err = self:state(scope)
  if not st then return nil, err end
  local removed = 0
  for _, e in ipairs(st:journal()) do
    if not st:get(e.name) and fs.exists(e.path) then
      fs.remove(e.path); removed = removed + 1
      local stop = e.path:find(self.cfg.appdir, 1, true) == 1 and self.cfg.appdir or st.root
      fs.prune(e.path:match("^(.*)/[^/]*$"), stop)
    end
  end
  st:clear_staging()
  st:unlock()
  return removed
end

-- Remove packages from a scope. Refuses while another record needs one, unless force.
function I:remove(names, scope, force)
  local st, err = self:state(scope)
  if not st then return nil, err, 1 end
  local gone = {}
  for _, n in ipairs(names) do gone[n] = true end
  for _, n in ipairs(names) do
    if not st:get(n) then return nil, n .. " is not installed in the " .. scope .. " scope", 1 end
  end
  if not force then
    for _, other in ipairs(st:names()) do
      if not gone[other] then
        local r = st:get(other)
        for dep in pairs(r and r.deps or {}) do
          if gone[dep] then return nil, ("%s is needed by %s (use --force to remove anyway)"):format(dep, other), 3 end
        end
      end
    end
  end
  local ok, lerr = st:lock()
  if not ok then return nil, lerr, 1 end
  local world = st:world()
  for _, n in ipairs(names) do
    self:remove_files(st, st:get(n))
    st:delete(n)
    world[n] = nil
  end
  st:set_world(world)
  st:unlock()
  return true
end

-- Verify installed files against their recorded hashes. Returns a list of problems.
function I:check(scope)
  local hashmod = require("vpm.hash")          -- only check needs it
  local st = self:state(scope)
  local problems = {}
  for _, n in ipairs(st:names()) do
    local r = st:get(n)
    local base = self:base_dir(st, r.kind, n)
    for f, want in pairs(r.files or {}) do
      local data = fs.read(base .. "/" .. f)
      if not data then problems[#problems + 1] = ("%s: missing %s"):format(n, f)
      elseif hashmod.hex(data) ~= want then problems[#problems + 1] = ("%s: modified %s"):format(n, f) end
    end
  end
  if fs.exists(st.dir .. "/lock") then problems[#problems + 1] = "stale lock file (a previous run did not finish)" end
  return problems
end

return M
