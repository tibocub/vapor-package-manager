-- Evaluate a rockspec (Lua code from the internet) with no access to the system, a step limit and no
-- way to load anything. Returns the table of globals the rockspec set, or nil, err.

local M = {}

local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type",
               "unpack", "_VERSION" }
local LIMIT = 2000000   -- VM instructions; a normal rockspec needs a few thousand

function M.load(text, name)
  local env = {}
  for _, k in ipairs(SAFE) do env[k] = _G[k] end
  env.string, env.table, env.math = string, table, math
  -- rockspecs sometimes read the platform or an environment variable; give harmless answers
  env.os = { getenv = function() return nil end, time = os.time, date = os.date }
  env.io = nil

  text = text:gsub("^#[^\n]*", "")   -- a leading #! line is legal in a file but not in load()
  local fn, err = load(text, "=" .. (name or "rockspec"), "t", env)
  if not fn then return nil, err end
  debug.sethook(function() error("rockspec took too long", 0) end, "", LIMIT)
  local ok, e = pcall(fn)
  debug.sethook()
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
