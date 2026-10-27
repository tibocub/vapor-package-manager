-- vpm remove pkg... : exact files from the record, refuses while something still needs the package.
return function(ctx, args)
  if #args == 0 then ctx.err("remove what? name one or more packages"); return 2 end
  local ok, err, code = ctx.maintainer():remove(args, ctx.scope, ctx.flags.force)
  if not ok then ctx.err("%s", err); return code or 1 end
  ctx.out("removed %s", table.concat(args, ", "))
  return 0
end
