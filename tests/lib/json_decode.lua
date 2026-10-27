-- Tiny JSON decoder for host tests only (a device uses the firmware's cjson).
local function decode(s)
  local pos = 1
  local function ws() pos = s:find("%S", pos) or #s + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local n = s:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
        else out[#out + 1] = map[n]; i = i + 2 end
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      repeat
        ws(); local k = str(); ws(); assert(s:sub(pos, pos) == ":"); pos = pos + 1
        t[k] = value(); ws(); local d = s:sub(pos, pos); pos = pos + 1
      until d == "}"
      return t
    elseif c == "[" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      repeat
        t[#t + 1] = value(); ws(); local d = s:sub(pos, pos); pos = pos + 1
      until d == "]"
      return t
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
      pos = pos + #num; return tonumber(num)
    end
  end
  local v = value(); ws()
  assert(pos > #s, "trailing data")
  return v
end
return decode
