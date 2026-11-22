-- vpm remove pkg... : exact files from the record, refuses while something still needs the package.
return function(ctx, args)
  if #args == 0 then ctx.err("remove what? name one or more packages"); return 2 end
  local ok, err, code = ctx.maintainer():remove(args, ctx.scope, ctx.flags.force)
  if not ok then ctx.err("%s", err); return code or 1 end
  ctx.out("removed %s", table.concat(args, ", "))
  if ctx.scope == "local" then      -- keep the lock in step: what is gone is no longer locked
    local Lock = require("vpm.lock")
    local lock = Lock.read(ctx)
    if lock then
      for _, n in ipairs(args) do if lock.roots[n] == nil then lock.packages[n] = nil end end   -- vpm.lua still asks for roots: they come back on the next vpm i
      Lock.write(ctx, lock)
    end
  end
  return 0
end
