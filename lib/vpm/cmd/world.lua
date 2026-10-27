-- vpm world : what you asked for, per scope.
return function(ctx)
  local any = false
  for _, scope in ipairs{ "global", "local" } do
    local w = ctx.state(scope):world()
    local names = {}
    for n in pairs(w) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      any = true
      ctx.out("%-22s %-10s %s", n, scope, w[n] ~= "" and w[n] or "any version")
    end
  end
  if not any then ctx.out("nothing was installed by name yet") end
  return 0
end
