-- vpm info NAME : what the index knows, and what is installed.
local version = require("vpm.version")

return function(ctx, args)
  local name = args[1]
  if not name then ctx.err("info about which package?"); return 2 end
  local index = ctx.index()
  local doc, err = index:package(name)
  if not doc then
    if err then ctx.err("%s", err); return 4 end
    ctx.out("%s is not in the index", name)
    return 1
  end
  local vs = {}
  for v in pairs(doc.versions) do vs[#vs + 1] = v end
  table.sort(vs, function(a, b) return version.less(b, a) end)
  local m = doc.versions[vs[1]]
  ctx.out("%s %s  (%s)", name, vs[1], doc.kind == "app" and "program" or "library")
  if m.summary then ctx.out("  %s", m.summary) end
  ctx.out("  versions:  %s", table.concat(vs, ", "))
  ctx.out("  depends:   %s", #(m.deps or {}) > 0 and table.concat(m.deps, ", ") or "nothing")
  ctx.out("  size:      %s", ctx.size(m.size))
  if m.license then ctx.out("  license:   %s", m.license) end
  if m.homepage then ctx.out("  homepage:  %s", m.homepage) end
  if m.host then ctx.out("  note:      written for %s", tostring(m.host)) end
  if m.blocked_by then ctx.out("  blocked:   needs %s, which is not available (%s)", m.blocked_by.name, tostring(m.blocked_by.reason)) end
  local n = m.native
  if n then
    local what = ({ c = "needs a C compiler", build = "needs a build step", other = "native code" })[n.native] or "native code"
    ctx.out("  native:    %s%s", what, (n.langs and #n.langs > 0) and (" (" .. table.concat(n.langs, ", ") .. ")") or "")
    if n.external then ctx.out("             system libraries: %s", table.concat(n.external, ", ")) end
    if n.build_deps then ctx.out("             build needs: %s", table.concat(n.build_deps, ", ")) end
  else
    ctx.out("  native:    no (pure Lua)")
  end
  for _, scope in ipairs{ "global", "local" } do
    local r = ctx.state(scope):get(name)
    if r then ctx.out("  installed: %s (%s)", r.version, scope) end
  end
  return 0
end
