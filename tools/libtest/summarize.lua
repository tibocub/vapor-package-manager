-- Reads OUT/results/*.tsv and prints a summary: per module and per package outcomes, and the failures grouped by cause.
--   vlr tools/libtest/summarize.lua OUT [detail]
local out, detail = arg[1], arg[2]
local p = io.popen("cat " .. out .. "/results/*.tsv")
local mods, pkgs = {}, {}
for l in p:lines() do
  -- name, module, then two results, each either "OK" or "ERR<TAB>message" (a tab inside), or INSTALL-FAILED/NO-MODULES followed by a message/empty
  local f = {}
  for t in (l .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = t end
  local name, mod, a, b = f[1], f[2], f[3], ""
  local i = 4
  if a == "ERR" then a = a .. "\t" .. (f[i] or ""); i = i + 1 end
  if f[i] then
    b = f[i]
    if b == "ERR" then b = b .. "\t" .. (f[i + 1] or "") end
  end
  mods[#mods + 1] = {name = name, mod = mod, a = a, b = b}
  pkgs[name] = pkgs[name] or {}
  table.insert(pkgs[name], mods[#mods])
end
p:close()

local function classify(r)
  r = (r:gsub("^ERR\t", ""))
  if r == "OK" then return "ok" end
  if r:match("^INSTALL%-FAILED") then return "install failed" end
  if r == "NO-OUTPUT" then return "crash or timeout (no output)" end
  if r == "NO-MODULES" then return "no modules listed" end
  local m = r:match("module '([^']+)' not found")
  if m then
    if m == "ffi" or m == "jit" or m:match("^jit%.") or m == "bit" then return "needs LuaJIT (" .. m .. ")" end
    if m:match("^vim") or m:match("^nvim") or m == "plenary" or m:match("^plenary") then return "needs Neovim (" .. m .. ")" end
    if m:match("^ngx") or m:match("^resty") then return "needs OpenResty (" .. m .. ")" end
    return "missing module: " .. m
  end
  if r:match("unexpected symbol") or r:match("syntax error") or r:match("'=' expected") or r:match("<eof> expected") or r:match("'end' expected") then return "syntax error (dialect?)" end
  if r:match("attempt to call a nil value %(field '[%w_]+'%)") then return "missing function: " .. (r:match("%(field '([%w_]+)'%)")) end
  if r:match("attempt to call a nil value %(global '[%w_]+'%)") then return "missing global: " .. (r:match("%(global '([%w_]+)'%)")) end
  if r:match("attempt to index a nil value %(global '[%w_]+'%)") then return "missing global: " .. (r:match("%(global '([%w_]+)'%)")) end
  return "other error"
end

local count = {ok51 = 0, ok54 = 0, both = 0, only51 = 0, only54 = 0, neither = 0}
local why = {}
local examples = {}
for _, m in ipairs(mods) do
  local c1, c2 = classify(m.a), classify(m.b == "" and m.a or m.b)
  if c1 == "ok" then count.ok51 = count.ok51 + 1 end
  if c2 == "ok" then count.ok54 = count.ok54 + 1 end
  if c1 == "ok" and c2 == "ok" then count.both = count.both + 1
  elseif c1 == "ok" then count.only51 = count.only51 + 1
  elseif c2 == "ok" then count.only54 = count.only54 + 1
  else
    count.neither = count.neither + 1
    why[c1] = (why[c1] or 0) + 1
    examples[c1] = examples[c1] or (m.name .. " " .. m.mod .. ": " .. m.a:sub(1, 120))
  end
end
print(("modules: %d   load in 5.1: %d   in 5.4: %d   both: %d   only 5.1: %d   only 5.4: %d   neither: %d"):format(#mods, count.ok51, count.ok54, count.both, count.only51, count.only54, count.neither))
local npk, pok = 0, 0
for _, list in pairs(pkgs) do
  npk = npk + 1
  local all = true
  for _, m in ipairs(list) do if classify(m.a) ~= "ok" and classify(m.b) ~= "ok" then all = false end end
  if all then pok = pok + 1 end
end
print(("packages: %d   every module loads in at least one dialect: %d (%.0f%%)"):format(npk, pok, 100 * pok / math.max(npk, 1)))
local list = {}
for k, v in pairs(why) do list[#list + 1] = {k, v} end
table.sort(list, function(x, y) return x[2] > y[2] end)
print("\nmodules that load in neither dialect, by cause:")
for i = 1, math.min(#list, detail and 200 or 25) do print(("%6d  %s"):format(list[i][2], list[i][1]), detail and ("   e.g. " .. examples[list[i][1]]) or "") end
