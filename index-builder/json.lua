-- Minimal deterministic JSON encoder (sorted keys, so index files diff cleanly). Arrays are tables with 1..n.
local M = {}

local esc = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return esc[c] or ("\\u%04x"):format(c:byte()) end) .. '"'
end

local function isarray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

function M.encode(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then return str(v)
  elseif t == "number" or t == "boolean" then return tostring(v)
  elseif t == "table" then
    local inner = indent .. "  "
    local out = {}
    if next(v) == nil then return "[]" end
    if isarray(v) then
      for i, x in ipairs(v) do out[i] = inner .. M.encode(x, inner) end
      return "[\n" .. table.concat(out, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for i, k in ipairs(keys) do out[i] = inner .. str(k) .. ": " .. M.encode(v[k], inner) end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. indent .. "}"
  end
  error("cannot encode " .. t)
end

-- Lua-table serialisation for the builder's own intermediate records (read back with dofile).
function M.lua_literal(v, indent)
  indent = indent or ""
  if type(v) == "string" then return ("%q"):format(v) end
  if type(v) ~= "table" then return tostring(v) end
  local inner, out = indent .. " ", {}
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do out[#out + 1] = inner .. "[" .. M.lua_literal(k) .. "] = " .. M.lua_literal(v[k], inner) end
  return "{\n" .. table.concat(out, ",\n") .. "\n" .. indent .. "}"
end

return M
