-- On-disk state of one scope (docs/state-and-tracking.md): <root>/.vpm/pkg/<name>.lua, one tiny record per
-- package, loaded one at a time with an empty environment; world.lua; lock; staging/.
local fs = require("vpm.fs")
local M = {}
local S = {}
S.__index = S

local function ser(v, ind)
  local t = type(v)
  if t == "string" then return ("%q"):format(v):gsub("\\\n", "\\n")
  elseif t == "number" or t == "boolean" then return tostring(v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local inner, out = ind .. "  ", {}
    for _, k in ipairs(keys) do
      local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k, inner) .. "]")
      out[#out + 1] = inner .. key .. " = " .. ser(v[k], inner)
    end
    if #out == 0 then return "{}" end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. ind .. "}"
  end
  error("cannot serialise " .. t)
end
M.serialise = function(v) return "return " .. ser(v, "") .. "\n" end

local function load_table(path)
  local f = fs.read(path)
  if not f then return nil end
  local chunk = load(f, "=" .. path, "t", {})
  if not chunk then return nil, "corrupt: " .. path end
  local ok, t = pcall(chunk)
  if not ok or type(t) ~= "table" then return nil, "corrupt: " .. path end
  return t
end

local function write_atomic(path, data)
  local tmp = path .. ".tmp"
  local ok, err = fs.write(tmp, data)
  if not ok then return nil, err end
  fs.remove(path)                 -- rename over an existing file is not portable to every NuttX filesystem
  return fs.rename(tmp, path)
end

function M.open(root)
  local s = setmetatable({ root = root, dir = root .. "/.vpm" }, S)
  fs.mkdirp(s.dir .. "/pkg")
  return s
end

function S:get(name) return load_table(("%s/pkg/%s.lua"):format(self.dir, name)) end

function S:names()
  local t = {}
  for _, f in ipairs(fs.list(self.dir .. "/pkg")) do
    local n = f:match("^(.*)%.lua$")
    if n then t[#t + 1] = n end
  end
  return t
end

-- name -> {version, deps} as the resolver wants it
function S:installed_view()
  local v = {}
  for _, n in ipairs(self:names()) do
    local r = self:get(n)
    if r then v[n] = { version = r.version, deps = r.deps or {}, kind = r.kind } end
  end
  return v
end

-- fresh = no record exists yet: write it directly (one flash operation instead of three); a torn new record
-- reads as corrupt, which vpm treats as "not installed" and `repair` cleans up.
function S:put(rec, fresh)
  local path = ("%s/pkg/%s.lua"):format(self.dir, rec.name)
  if fresh then return fs.write(path, M.serialise(rec)) end
  return write_atomic(path, M.serialise(rec))
end
function S:delete(name) return fs.remove(("%s/pkg/%s.lua"):format(self.dir, name)) end

function S:world() return load_table(self.dir .. "/world.lua") or {} end
function S:set_world(w) return write_atomic(self.dir .. "/world.lua", M.serialise(w)) end

function S:staging(name) return self.dir .. "/staging/" .. (name or "") end
function S:clear_staging() fs.rmtree(self.dir .. "/staging") end

-- The lock file doubles as the journal: its content is "name<TAB>path" lines for every file this run creates in
-- place (not through staging), so a crashed run can be undone (installer :repair).
function S:lock(journal)
  local p = self.dir .. "/lock"
  if fs.exists(p) then return nil, "another vpm run is active or crashed (see 'vpm check'): " .. p end
  return fs.write(p, journal or tostring(os.time()))
end
function S:journal()
  local t = {}
  for line in (fs.read(self.dir .. "/lock") or ""):gmatch("[^\n]+") do
    local name, path = line:match("^([^\t]+)\t(.+)$")
    if name then t[#t + 1] = { name = name, path = path } end
  end
  return t
end
function S:unlock() fs.remove(self.dir .. "/lock") end

return M
