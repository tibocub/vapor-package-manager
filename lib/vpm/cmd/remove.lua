-- vpm remove pkg... : exact files from the record, refuses while something still needs the package.
return function(ctx, args)
  if #args == 0 then ctx.err("remove what? name one or more packages"); return 2 end
  local installer = ctx.installer()
  local ok, err, code = installer:remove(args, ctx.scope, ctx.flags.force)
  if not ok then ctx.err("%s", err); return code or 1 end
  ctx.out("removed %s", table.concat(args, ", "))
  return 0
end
