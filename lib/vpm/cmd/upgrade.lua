-- vpm upgrade [pkg...] : move named (or all world) packages to the newest version their constraint allows.
local plan_ui = require("vpm.plan")
local version = require("vpm.version")

return function(ctx, args)
  local installer, index = ctx.installer()
  local st = ctx.state(ctx.scope)
  local world = st:world()
  local names = args
  if #names == 0 then
    names = {}
    for n in pairs(world) do names[#names + 1] = n end
    table.sort(names)
  end
  local requests, requested = {}, {}
  for _, n in ipairs(names) do
    local rec = st:get(n)
    if not rec then ctx.err("%s is not installed (%s)", n, ctx.scope); return 1 end
    local cs = version.parse_constraints(world[n] or "") or {}
    local doc = index:package(n)
    local best
    for v in pairs(doc and doc.versions or {}) do
      if not v:match("^scm") and not v:match("^dev") and version.satisfies(v, cs)
         and (not best or version.less(best, v)) then best = v end
    end
    if best and version.less(rec.version, best) then
      requests[#requests + 1] = { name = n, constraint = "== " .. best }
      requested[n] = world[n] or ""
    else
      ctx.out("%s %s is up to date", n, rec.version)
    end
  end
  if #requests == 0 then return 0 end

  local plan, err = require("vpm.resolver").resolve{
    requests = requests, scope = ctx.scope, deps = ctx.flags.deps or ctx.cfg.deps or "auto", provided = ctx.provided(),
    installed = { global = ctx.state("global"):installed_view(), ["local"] = ctx.state("local"):installed_view() },
    index = function(n) return index:resolver_view(n) end,
  }
  if not plan then ctx.err("%s", err); return 3 end
  plan_ui.show(ctx, plan)
  if ctx.flags.dry_run then return 0 end
  if not ctx.flags.yes then
    ctx.out("Download: %s", ctx.size(plan.download))
    local yes = ctx.ask("Continue?")
    if yes == nil then ctx.err("this needs confirmation and there is no terminal: use -y"); return 1 end
    if not yes then ctx.out("aborted"); return 1 end
  end
  local ok, aerr, code = installer:apply(plan, requested)
  if not ok then ctx.err("%s", aerr); return code or 1 end
  ctx.out("upgraded %d package(s)", plan_ui.installs(plan))
  return 0
end
