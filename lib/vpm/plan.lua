-- Presenting a resolver plan, and deciding whether to ask (docs/spec.md, "Prompting").
local M = {}

local function line(a, size)
  local what = a.action
  local ver = a.version
  if a.replaces then what = "upgrade"; ver = a.replaces .. " -> " .. a.version end
  local extra = a.shadows and ("  (shadows %s %s)"):format("global", a.shadows) or ""
  if a.action == "install" and a.size then extra = ("  %s"):format(size(a.size)) .. extra end
  return ("  %-8s %-18s %-9s %s%s"):format(what, a.name, a.scope, ver, extra)
end

-- Print the plan. requested = set of names the user named.
function M.show(ctx, plan)
  for _, a in ipairs(plan.actions) do ctx.out(line(a, ctx.size)) end
  for _, b in ipairs(plan.breaks or {}) do
    ctx.out("  warning: %s needs %s %s, which this would break", b.by, b.name, b.needs)
  end
end

-- true when the plan does more than install the packages the user named
function M.needs_prompt(plan, requested, scope)
  if #(plan.breaks or {}) > 0 then return true end
  for _, a in ipairs(plan.actions) do
    if a.action == "install" then
      if not requested[a.name] or a.replaces or a.shadows then return true end
      if a.scope == "global" and scope == "local" then return true end
    end
  end
  return false
end

function M.installs(plan)
  local n = 0
  for _, a in ipairs(plan.actions) do if a.action == "install" then n = n + 1 end end
  return n
end

return M
