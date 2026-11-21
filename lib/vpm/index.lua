-- Index client: one small JSON file per package (docs/index-and-network.md), fetched on demand and cached for the
-- run. `decode` is the firmware's cjson.decode on a device; tests pass their own. Remote data is never `load`ed.
local M = {}
local I = {}
I.__index = I

-- same rule as index-builder/build.lua
local function shard(name) return (name:sub(1, 2):lower():gsub("[^%w]", "_")) end

-- o.keys (list of 32-byte public keys) turns signature checking on: every index file must then come with a valid
-- FILE.sig from one of them (docs/signing.md). o.verify(sig, msg, key) -> bool is vsign.verify on a device.
-- o.serial_file remembers the highest meta serial seen, so an older (rolled-back) index is refused.
function M.new(o)
  return setmetatable({ base = o.base:gsub("/$", ""), transport = o.transport, decode = o.decode, cache = {},
                        keys = o.keys, verify = o.verify, serial_file = o.serial_file }, I)
end

-- body of an index file, signature-checked when keys are configured; nil, status, err on failure
function I:fetch(path)
  local url = self.base .. "/" .. path
  local body, status, err = self.transport.fetch(url)
  if not body or not self.keys then return body, status, err end
  local sig = self.transport.fetch(url .. ".sig")
  if not sig or #sig ~= 64 then return nil, 495, "no valid signature for " .. path end
  local verify = self.verify
  if not verify then
    local ok, mod = pcall(require, "vapor.sign") -- vlr's name; vlua called it vsign
    verify = (ok and mod or require("vsign")).verify
  end
  for _, key in ipairs(self.keys) do
    if verify(sig, body, key) then return body end
  end
  return nil, 495, "bad signature on " .. path .. " (not signed by a trusted key)"
end

-- meta.json, checked once per run; with keys, also refuses a serial lower than the last one seen
function I:meta()
  if self.meta_doc == nil then
    local body, status, err = self:fetch("meta.json")
    if not body then return nil, status, err end
    local ok, doc = pcall(self.decode, body)
    if not ok or type(doc) ~= "table" then return nil, 400, "bad meta.json" end
    if self.keys and self.serial_file then
      local f = io.open(self.serial_file, "r")
      local seen = f and tonumber(f:read("a")) or 0
      if f then f:close() end
      if type(doc.serial) ~= "number" then return nil, 495, "signed meta.json has no serial" end
      if doc.serial < seen then return nil, 495, ("index is older than one already seen (serial %d < %d)"):format(doc.serial, seen) end
      if doc.serial > seen then
        require("vpm.fs").mkdirp(self.serial_file:match("^(.*)/[^/]*$"))
        local w = io.open(self.serial_file, "w")
        if w then w:write(tostring(doc.serial)); w:close() end
      end
    end
    self.meta_doc = doc
  end
  return self.meta_doc
end

-- a package that comes from a directory instead of the index (vpm install ./dir)
function I:add_local(doc) self.cache[doc.name] = doc end

function I:package(name)
  local c = self.cache[name]
  if c ~= nil then return c or nil end
  if self.keys then
    local _, mstatus, merr = self:meta()          -- the signed meta (and its serial) is checked before any package
    if self.meta_doc == nil then return nil, merr or ("index error " .. tostring(mstatus)) end
  end
  local body, status, err = self:fetch(("p/%s/%s.json"):format(shard(name), name))
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
