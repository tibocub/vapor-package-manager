-- A package that lives in a directory (vpm install ./dir): build an index entry in memory, with file:// URLs and
-- hashes, so the normal resolve / verify / place path installs it. The directory's vpm.lua says what it is:
--   return { name = "x", version = "0.1.0", kind = "lib"|"app", bin = { cmd = "main.lua" },
--            deps = { lpeg = ">= 1.0" }, description = "...", files = { "x.lua", "x/y.lua" } }
-- Without `files`, every .lua file is installed except vpm.lua, vpm-lock.lua and the directories lua_modules,
-- tests, test, spec and anything starting with a dot.
local fs = require("vpm.fs")
local hashmod = require("vpm.hash")
local M = {}

local SKIP_DIRS = { lua_modules = true, tests = true, test = true, spec = true }
local SKIP_FILES = { ["vpm.lua"] = true, ["vpm-lock.lua"] = true }

local function scan(dir, rel, out)
  for _, n in ipairs(fs.list(dir)) do
    local path = dir .. "/" .. n
    if n:sub(1, 1) ~= "." then
      if fs.isdir(path) then
        if not SKIP_DIRS[n] then scan(path, rel .. n .. "/", out) end
      elseif n:match("%.lua$") and not (rel == "" and SKIP_FILES[n]) then
        out[#out + 1] = rel .. n
      end
    end
  end
end

function M.load(dir)
  dir = dir:gsub("/+$", "")
  local src = fs.read(dir .. "/vpm.lua")
  if not src then return nil, dir .. " has no vpm.lua (name and version are required)" end
  local chunk = load(src, "=" .. dir .. "/vpm.lua", "t", {})
  local ok, m = pcall(chunk or error, "syntax error")
  if not ok or type(m) ~= "table" then return nil, dir .. "/vpm.lua is not a valid manifest" end
  if type(m.name) ~= "string" or not m.name:match("^[%w][%w%._%-]*$") then return nil, "vpm.lua needs a valid name" end
  if type(m.version) ~= "string" or m.version == "" then return nil, "vpm.lua needs a version" end

  local list = m.files
  if not list then list = {}; scan(dir, "", list) end
  table.sort(list)
  if #list == 0 then return nil, "no .lua files to install in " .. dir end

  local files, size = {}, 0
  for _, dest in ipairs(list) do
    local data, err = fs.read(dir .. "/" .. dest)
    if not data then return nil, "cannot read " .. dest .. ": " .. tostring(err) end
    files[dest] = { sha256 = hashmod.hex(data), size = #data, url = "file://" .. dir .. "/" .. dest }
    size = size + #data
  end

  local deps, names = {}, {}
  for n in pairs(m.deps or {}) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do deps[#deps + 1] = (n .. " " .. m.deps[n]):gsub("%s+$", "") end

  return { name = m.name, kind = m.kind == "app" and "app" or "lib", versions = { [m.version] = {
    deps = deps, files = files, bin = m.bin or {}, size = size, summary = m.description,
    origin = { type = "dir", url = dir } } } }
end

return M
