-- lua index-builder/run.lua list   MANIFEST            -> "name version" lines (newest release of each rock)
-- lua index-builder/run.lua report MANIFEST DIR        -> run the filter over the downloaded rockspecs
package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local manifest, sandbox, filter = require("manifest"), require("sandbox"), require("filter")

local cmd, mpath, dir = arg[1], arg[2], arg[3]
local repo = manifest.load(mpath)

local names = {}
for name in pairs(repo) do names[#names + 1] = name end
table.sort(names)

if cmd == "list" then
  for _, name in ipairs(names) do print(name, manifest.latest(repo[name])) end
  return
end

local _, checked, stats = require("evaluate")(repo, dir)
local bad = { read = stats.missing, eval = stats.eval }
local evalerr = {}

local status, root = filter.closure(checked)
local acc, reasons = {}, {}
for name, st in pairs(status) do
  if st == true then acc[#acc + 1] = name
  else
    local key = tostring(st)
    if st == "dep" then key = "dep (root cause: " .. tostring(root[name].reason):gsub(":.*", "") .. ")" end
    reasons[key] = (reasons[key] or 0) + 1
  end
end
table.sort(acc)

local total = #names
print(("rocks: %d   rockspec missing: %d   rockspec failed to evaluate: %d"):format(total, bad.read, bad.eval))
local tagged = {}
for _, n in ipairs(acc) do local h = checked[n].host; if h then tagged[h] = (tagged[h] or 0) + 1 end end
print(("ACCEPTED (pure Lua, closure ok): %d  (%.1f%%)"):format(#acc, 100 * #acc / total))
for h, n in pairs(tagged) do print(("   of which tagged host=%s: %d"):format(h, n)) end
local rl = {}
for k, n in pairs(reasons) do rl[#rl + 1] = { k, n } end
table.sort(rl, function(a, b) return a[2] > b[2] end)
print("rejected, by first reason:")
for _, r in ipairs(rl) do print(("  %5d  %s"):format(r[2], r[1])) end

do   -- the rocks most often responsible for rejecting their dependents
  local culprit = {}
  for name, st in pairs(status) do
    if st == "dep" then local r = root[name]; culprit[r.name .. " (" .. r.reason:gsub(":.*", "") .. ")"] =
      (culprit[r.name .. " (" .. r.reason:gsub(":.*", "") .. ")"] or 0) + 1 end
  end
  local cl = {}
  for k, n in pairs(culprit) do cl[#cl + 1] = { k, n } end
  table.sort(cl, function(a, b) return a[2] > b[2] end)
  print("rocks that block the most dependents:")
  for i = 1, math.min(12, #cl) do print(("  %5d  %s"):format(cl[i][2], cl[i][1])) end
end

if arg[4] then
  local out = assert(io.open(arg[4], "w"))
  for _, n in ipairs(acc) do out:write(n, " ", checked[n].version, "\n") end
  out:close()
  print("accepted list written to " .. arg[4])
end
if #evalerr > 0 then print("first eval errors:"); for i = 1, math.min(5, #evalerr) do print("  " .. evalerr[i]) end end
