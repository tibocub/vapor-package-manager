-- LuaRocks manifest-5.x: load it (it is a Lua table literal; evaluated with an empty environment) and pick versions.
local V = require("vpm.version")

local M = {}

function M.load(path)
  local env = {}
  local f = assert(loadfile(path, "t", env))
  f()
  return env.repository or {}
end

local function special(v) return v:match("^scm") or v:match("^dev") or v:match("^cvs") end

-- newest release version of a rock; falls back to the newest scm/dev one if there is no release
function M.latest(versions)
  local best, bestspecial
  for v in pairs(versions) do
    if special(v) then
      if not bestspecial or V.less(bestspecial, v) then bestspecial = v end
    elseif not best or V.less(best, v) then
      best = v
    end
  end
  return best or bestspecial
end

-- all rockspec-bearing versions, newest first
function M.versions(versions)
  local list = {}
  for v, entries in pairs(versions) do
    for _, e in ipairs(entries) do
      if e.arch == "rockspec" then list[#list + 1] = v; break end
    end
  end
  table.sort(list, function(a, b) return V.less(b, a) end)
  return list
end

return M
