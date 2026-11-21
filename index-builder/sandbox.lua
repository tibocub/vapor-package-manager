-- Evaluate a rockspec (Lua code from the internet) with no access to the system, a step limit and no
-- way to load anything. Returns the table of globals the rockspec set, or nil, err.

local M = {}

local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type",
               "unpack", "_VERSION" }
local LIMIT = 2000000   -- VM instructions; a normal rockspec needs a few thousand

function M.load(text, name)
  local env = {}
  for _, k in ipairs(SAFE) do env[k] = _G[k] end
  -- copies, so a rockspec that assigns to string.x cannot change what the builder or the next rockspec sees; the C functions that can burn
  -- memory or time without running a single VM instruction (which the step limit counts) are bounded: rep output, and pattern work on short subjects
  local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
  env.string, env.table, env.math = copy(string), copy(table), copy(math)
  local S = env.string
  S.rep = function(str, n, sep)
    if type(str) ~= "string" or type(n) ~= "number" then return string.rep(str, n, sep) end
    if #str * math.max(n, 0) + #(sep or "") * math.max(n - 1, 0) > 65536 then error("string.rep too large", 2) end
    return string.rep(str, n, sep)
  end
  for _, name in ipairs { "find", "match", "gmatch", "gsub" } do
    local orig = string[name]
    S[name] = function(str, pat, ...)
      if type(str) == "string" and type(pat) == "string" and (#str > 512 or #pat > 64) then error("pattern work too large", 2) end
      return orig(str, pat, ...)
    end
  end
  env.table.concat = function(t, sep, i, j)
    local out = table.concat(t, sep, i, j)
    if #out > 262144 then error("string too large", 2) end
    return out
  end
  -- rockspecs sometimes read the platform or an environment variable; give harmless answers
  env.os = { getenv = function() return nil end, time = os.time, date = os.date }
  env.io = nil

  text = text:gsub("^#[^\n]*", "")   -- a leading #! line is legal in a file but not in load()
  local fn, err = load(text, "=" .. (name or "rockspec"), "t", env)
  if not fn then return nil, err end
  -- ("x"):rep(n) looks the method up through the shared string metatable, which would bypass the bounded copies above: point it at them while the rockspec runs
  local mt = getmetatable("")
  local old_index = mt.__index
  mt.__index = env.string
  debug.sethook(function() error("rockspec took too long", 0) end, "", LIMIT)
  local ok, e = pcall(fn)
  debug.sethook()
  mt.__index = old_index
  if not ok then return nil, tostring(e) end

  local out = {}
  for k, v in pairs(env) do
    out[k] = v
  end
  for _, k in ipairs(SAFE) do out[k] = nil end
  out.string, out.table, out.math, out.os = nil, nil, nil, nil
  return out
end

return M
