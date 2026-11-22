-- vpm-lock.lua: exact versions and an integrity digest for everything a project resolved (like package-lock.json).
--   return { lockfile = 1, roots = { name = "constraint" }, packages = { name = { version = "1.0-1", digest = "<sha256>" } } }
-- `vpm i` without arguments installs exactly this when it still matches vpm.lua (roots equal), and refuses when the index now holds different bytes for a locked version
-- (the digest covers the file names and sha256 of the package's files). A lock is written by the first `vpm i` and updated by named installs and removals.
local fs, hash, state = require("vpm.fs"), require("vpm.hash"), require("vpm.state")
local M = {}

-- files: dest -> { sha256 = ... } (index entry) or dest -> "sha256" (installed record)
function M.digest(files)
  local dests = {}
  for d in pairs(files or {}) do dests[#dests + 1] = d end
  table.sort(dests)
  local parts = {}
  for _, d in ipairs(dests) do
    local f = files[d]
    parts[#parts + 1] = d .. " " .. (type(f) == "table" and f.sha256 or f)
  end
  return hash.hex(table.concat(parts, "\n"))
end

function M.path(ctx) return ctx.cwd .. "/vpm-lock.lua" end

-- nil when there is no lock (or an old-format one that did not hold what we need); nil, message when it is damaged
function M.read(ctx)
  local f = io.open(M.path(ctx), "rb")
  if not f then return nil end
  local text = f:read("a"); f:close()
  local chunk = load(text, "=vpm-lock.lua", "t", {})
  local ok, t = pcall(chunk or error, "bad")
  if not ok or type(t) ~= "table" then return nil, "vpm-lock.lua is damaged" end
  if t.lockfile == nil then return nil end                       -- the format before 2026-11-22 recorded versions only
  if t.lockfile ~= 1 then return nil, "vpm-lock.lua was written by a newer vpm" end
  if type(t.packages) ~= "table" or type(t.roots) ~= "table" then return nil, "vpm-lock.lua is damaged" end
  return t
end

function M.write(ctx, lock)
  lock.lockfile = 1
  return fs.write(M.path(ctx), state.serialise(lock))
end

function M.same_roots(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

-- digest of a version as the index describes it; nil for a package that does not come from the index
function M.index_digest(index, name, version)
  local doc = index:package(name)
  local m = doc and doc.versions[version]
  return m and M.digest(m.files)
end

-- packages for a plan: name -> { version, digest }
function M.from_plan(index, plan)
  local pk = {}
  for _, a in ipairs(plan.actions) do
    pk[a.name] = { version = a.version, digest = M.index_digest(index, a.name, a.version) }
  end
  return pk
end

return M
