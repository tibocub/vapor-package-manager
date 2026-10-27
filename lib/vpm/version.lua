-- Versions and dependency constraints, with exactly the semantics of LuaRocks (luarocks/core/vers.lua and
-- queries.lua, MIT licensed) so that rockspec data means the same thing here. Pure Lua, small, no I/O.
--
-- A parsed version is a table of numbers plus .revision and .string, with <, <=, == defined.
-- Note "~>" is LuaRocks' PREFIX match, not Ruby's pessimistic operator: "~> 1.2" matches 1.2 and 1.2.x
-- but not 1.3.

local M = {}

local deltas = { dev = 120000000, scm = 110000000, cvs = 100000000,
                 rc = -1000, pre = -10000, beta = -100000, alpha = -1000000 }

local mt = {}
mt.__eq = function(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  if a.revision and b.revision then return a.revision == b.revision end
  return true
end
mt.__lt = function(a, b)
  for i = 1, math.max(#a, #b) do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then return x < y end
  end
  if a.revision and b.revision then return a.revision < b.revision end
  return false
end
mt.__le = function(a, b) return not (b < a) end
mt.__tostring = function(v) return v.string end

function M.parse(s)
  if type(s) ~= "string" then return nil end
  local v, i = {}, 1
  local str = s:match("^%s*(.-)%s*$")
  v.string = str
  local main, rev = str:match("(.*)%-(%d+)$")
  if rev then str = main; v.revision = tonumber(rev) end
  while #str > 0 do
    local tok, rest = str:match("^(%d+)[%.%-%_]*(.*)")
    if tok then
      v[i] = tonumber(tok)
    else
      tok, rest = str:match("^(%a+)[%.%-%_]*(.*)")
      if not tok then return nil end
      v[i] = deltas[tok] or (tok:byte() / 1000)
    end
    i = i + 1
    str = rest
  end
  return setmetatable(v, mt)
end

-- "~>": every component given in the constraint must be equal (missing ones count as 0) [LuaRocks partial_match]
local function partial(v, req)
  for i, r in ipairs(req) do
    if r ~= (v[i] or 0) then return false end
  end
  if req.revision then return req.revision == v.revision end
  return true
end

local ops = { ["=="] = "==", ["~="] = "~=", [">"] = ">", ["<"] = "<", [">="] = ">=", ["<="] = "<=",
              ["~>"] = "~>", [""] = "==", ["="] = "==", ["!="] = "~=" }

-- ">= 1.0, < 2" -> { {op=">=", version=v}, {op="<", version=v} } or nil, err
function M.parse_constraints(input)
  local list = {}
  input = input or ""
  while #input > 0 do
    local op, ver, rest = input:match("^@?([<>=~!]*)%s*([%w%.%_%-]+)[%s,]*(.*)")
    if not op then return nil, "bad constraint: " .. input end
    if not ops[op] then return nil, "bad operator '" .. op .. "'" end
    local pv = M.parse(ver)
    if not pv then return nil, "bad version '" .. ver .. "'" end
    list[#list + 1] = { op = ops[op], version = pv }
    input = rest
  end
  return list
end

-- "lpeg >= 0.12, < 2" -> { name = "lpeg", constraints = {...} } or nil, err
function M.parse_dep(s)
  local name, rest = s:match("^%s*([a-zA-Z0-9%.%-%_]*/?[a-zA-Z0-9][a-zA-Z0-9%.%-%_]*)%s*([^/]*)")
  if not name then return nil, "no dependency name in '" .. s .. "'" end
  local c, err = M.parse_constraints(rest)
  if not c then return nil, err end
  return { name = name, constraints = c }
end

-- version (string or parsed) against a constraint list
function M.satisfies(version, constraints)
  if type(version) == "string" then version = M.parse(version) end
  if not version then return false end
  for _, c in ipairs(constraints) do
    local cv, ok = c.version, nil
    if c.op == "==" then ok = version == cv
    elseif c.op == "~=" then ok = version ~= cv
    elseif c.op == ">" then ok = version > cv
    elseif c.op == "<" then ok = version < cv
    elseif c.op == ">=" then ok = version >= cv
    elseif c.op == "<=" then ok = version <= cv
    elseif c.op == "~>" then ok = partial(version, cv)
    end
    if not ok then return false end
  end
  return true
end

-- a < b ordering helper for sort (newest first: use compare(b, a))
function M.less(a, b)
  return (type(a) == "string" and M.parse(a) or a) < (type(b) == "string" and M.parse(b) or b)
end

return M
