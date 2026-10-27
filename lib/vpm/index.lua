-- Index client: one small JSON file per package (docs/index-and-network.md), fetched on demand and cached for the
-- run. `decode` is the firmware's cjson.decode on a device; tests pass their own. Remote data is never `load`ed.
local M = {}
local I = {}
I.__index = I

-- same rule as index-builder/build.lua
local function shard(name) return (name:sub(1, 2):lower():gsub("[^%w]", "_")) end

function M.new(o)
  return setmetatable({ base = o.base:gsub("/$", ""), transport = o.transport, decode = o.decode, cache = {} }, I)
end

-- a package that comes from a directory instead of the index (vpm install ./dir)
function I:add_local(doc) self.cache[doc.name] = doc end

function I:package(name)
  local c = self.cache[name]
  if c ~= nil then return c or nil end
  local body, status, err = self.transport.fetch(("%s/p/%s/%s.json"):format(self.base, shard(name), name))
  if not body then
    if status == 404 then self.cache[name] = false; return nil end
    return nil, err or ("index error " .. tostring(status))
  end
  local ok, doc = pcall(self.decode, body)
  if not ok or type(doc) ~= "table" or doc.name ~= name then return nil, "bad index data for " .. name end
  self.cache[name] = doc
  return doc
end

-- the view the resolver wants: { versions = { [v] = { deps = {...}, size = n } } }
function I:resolver_view(name)
  local doc = self:package(name)
  if not doc then return nil end
  local vs = {}
  for v, m in pairs(doc.versions) do vs[v] = { deps = m.deps or {}, size = m.size } end
  return { versions = vs, kind = doc.kind }
end

return M
