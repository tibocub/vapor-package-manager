-- vpm list [-g] : installed packages of one scope; for the global scope also files nobody owns.
local fs = require("vpm.fs")

local function walk(dir, rel, owned, out)
  for _, n in ipairs(fs.list(dir)) do
    local path, r = dir .. "/" .. n, rel .. n
    if rel == "" and n == ".vpm" then
    elseif fs.isdir(path) then walk(path, r .. "/", owned, out)
    elseif n:match("%.lua$") and not owned[r] then out[#out + 1] = r end
  end
end

return function(ctx)
  local st = ctx.state(ctx.scope)
  local names = st:names()
  local owned = {}
  if #names == 0 then ctx.out("nothing installed (%s)", ctx.scope) end
  for _, n in ipairs(names) do
    local r = st:get(n)
    if r then
      ctx.out("%-22s %-14s %-4s %s", n, r.version, r.kind == "app" and "app" or "lib", r.reason == "world" and "world" or "dep")
      for f in pairs(r.files or {}) do owned[f] = true end
    else
      ctx.out("%-22s (unreadable record)", n)
    end
  end
  if ctx.scope == "global" and ctx.cfg.libdir and fs.isdir(ctx.cfg.libdir) then
    local un = {}
    walk(ctx.cfg.libdir, "", owned, un)
    table.sort(un)
    for _, f in ipairs(un) do ctx.out("%-22s (unmanaged)", f) end
  end
  return 0
end
