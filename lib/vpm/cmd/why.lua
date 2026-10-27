-- vpm why NAME : everything that uses NAME, in the global tree, here, and in registered projects.
local fs = require("vpm.fs")
local State = require("vpm.state")

return function(ctx, args)
  local name = args[1]
  if not name then ctx.err("why which package?"); return 2 end
  local found = 0
  local function scan(st, label)
    local r = st:get(name)
    if r then ctx.out("%s %s is installed (%s)", name, r.version, label) end
    for _, n in ipairs(st:names()) do
      local o = st:get(n)
      if o and o.deps and o.deps[name] ~= nil then
        found = found + 1
        ctx.out("  %-20s %-12s (%s, %s)   needs %s %s", o.name, o.version, o.kind == "app" and "program" or "library",
          label, name, o.deps[name])
      end
    end
  end
  local prov = ctx.cfg.provided or ctx.provided()
  if prov[name] then ctx.out("%s %s is provided by the firmware", name, prov[name]) end
  if ctx.cfg.libdir then scan(ctx.state("global"), "global") end
  if ctx.cwd ~= nil then scan(ctx.state("local"), "this project") end
  if ctx.cfg.libdir then
    for path in pairs(ctx.state("global"):projects()) do
      if path ~= ctx.cwd and fs.isdir(path .. "/lua_modules/.vpm") then
        scan(State.open(path .. "/lua_modules"), "project " .. path)
      end
    end
  end
  if found == 0 then ctx.out("nothing installed depends on %s", name) end
  return 0
end
