-- vpm check [--repair] : hashes of installed files, stale locks; --repair undoes a crashed run.
local fs = require("vpm.fs")

return function(ctx)
  local installer = ctx.maintainer()
  local bad = 0
  for _, scope in ipairs{ "global", "local" } do
    local st = ctx.state(scope)
    if fs.isdir(st.dir) then
      if ctx.flags.repair and fs.exists(st.dir .. "/lock") then
        ctx.out("%s: removed %d leftover file(s) of an interrupted run", scope, installer:repair(scope))
      end
      for _, p in ipairs(installer:check(scope)) do ctx.out("%s: %s", scope, p); bad = bad + 1 end
    end
  end
  if bad == 0 then ctx.out("all installed files match their records") end
  return bad == 0 and 0 or 1
end
