-- Dependency resolver: pure logic, no I/O (docs/dependency-resolution.md).
--
--   resolve{
--     requests  = { { name = "penlight", constraint = ">= 1.14" }, ... },   -- constraint optional
--     scope     = "local" | "global",          -- where the user asked to install
--     deps      = "auto" | "global" | "local", -- where new dependencies go for a local install
--     provided  = { lpeg = "1.1.0" },          -- firmware libraries, by rock name
--     installed = { global = { name = { version = "1-1", deps = { other = ">= 1" } } }, ["local"] = {...} },
--     index     = function(name) -> { versions = { ["1.0-1"] = { deps = { "lpeg >= 1" }, size = 100 } } } | nil,
--   }
--   -> plan, or nil + error message naming the chain.
--
-- plan = { actions = { {name, version, action = "install"|"reuse", scope = "global"|"local"|"firmware",
--                       shadows = version?, replaces = version?, size = n?} ... },   -- dependencies first
--          breaks = { {name, needs = "..", by = pkg} ... }, download = bytes }
--
-- One version per name per process: backtracking picks one candidate per name, in the order
-- firmware, local, global, index (highest first).

local version = require("vpm.version")
local M = {}

local function is_unreleased(v) return v:match("^scm") or v:match("^dev") end

local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end

-- "name >= 1" or { name = ">= 1" } entries -> list of { name, constraints, text }
local function parse_deps(list, is_map)
  local out = {}
  if is_map then
    local names = {}
    for n in pairs(list) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      local c = version.parse_constraints(list[n])
      out[#out + 1] = { name = n, constraints = c or {}, text = n .. " " .. list[n] }
    end
  else
    for _, s in ipairs(list or {}) do
      local d = version.parse_dep(s)
      if d and d.name ~= "lua" then d.text = s; out[#out + 1] = d end
    end
  end
  return out
end

local function satisfies_all(v, reqs)
  for _, r in ipairs(reqs) do
    if not version.satisfies(v, r.constraints) then return false end
  end
  return true
end

local function describe(reqs)
  local parts = {}
  for _, r in ipairs(reqs) do
    local c = r.text:match("^%S+%s+(.*)$")
    parts[#parts + 1] = ("%s (from %s)"):format((c and c ~= "") and c or "any version", r.by)
  end
  return table.concat(parts, ", ")
end

function M.resolve(o)
  local provided, installed = o.provided or {}, o.installed or {}
  local policy = o.deps or "auto"
  local index_cache = {}
  local function lookup(name)
    if index_cache[name] == nil then index_cache[name] = o.index(name) or false end
    return index_cache[name] or nil
  end
  local best_err, best_depth

  -- keep the most specific explanation: deepest first; a generic "no combination" only if nothing better exists
  local function fail(msg, depth, generic)
    if generic then best_err = best_err or msg return end
    if not best_depth or depth >= best_depth then best_err, best_depth = msg, depth end
  end

  -- where a package newly installed from the index goes
  local function new_scope(name, req_scope, user_named)
    if req_scope == "global" then return "global" end
    if user_named then return o.scope end
    if policy == "global" then return "global" end
    if policy == "local" then return "local" end
    local g = (installed.global or {})[name]
    return g and "local" or "global"      -- auto: global unless a different version is installed globally
  end

  local function candidates(name, reqs, global_only, user_named)
    local list = {}
    if provided[name] and satisfies_all(provided[name], reqs) then
      list[#list + 1] = { version = provided[name], source = "firmware", scope = "firmware", deps = {} }
    end
    for _, sc in ipairs(global_only and { "global" } or { "local", "global" }) do
      local rec = (installed[sc] or {})[name]
      if rec and satisfies_all(rec.version, reqs) then
        list[#list + 1] = { version = rec.version, source = "installed", scope = sc,
                            deps = parse_deps(rec.deps, true) }
      end
    end
    local idx = lookup(name)
    if idx then
      local names = {}
      for v in pairs(idx.versions) do names[#names + 1] = v end
      table.sort(names, function(a, b) return version.less(b, a) end)
      local explicit = false     -- unreleased (scm/dev) only when a constraint names one
      for _, r in ipairs(reqs) do
        for _, c in ipairs(r.constraints) do if is_unreleased(c.version.string) then explicit = true end end
      end
      for _, v in ipairs(names) do
        if (not is_unreleased(v) or explicit) and satisfies_all(v, reqs) then
          local scope = new_scope(name, global_only and "global" or nil, user_named)
          local meta = idx.versions[v]
          local deps = parse_deps(meta.deps)
          list[#list + 1] = { version = v, source = "index", scope = scope, size = meta.size, deps = deps }
          if scope == "global" and policy == "auto" and not global_only and not user_named then
            -- fallback when a global copy cannot work (it needs something only available locally)
            list[#list + 1] = { version = v, source = "index", scope = "local", size = meta.size, deps = deps }
          end
        end
      end
    end
    return list
  end

  -- state: chosen[name] = candidate (+ name), reqs[name] = list of {constraints,text,by,scope}, pending = list
  local function solve(chosen, reqs, pending, depth)
    if #pending == 0 then return chosen end
    local name = pending[1]
    local rest = { table.unpack(pending, 2) }
    if chosen[name] then return solve(chosen, reqs, rest, depth) end

    local rl = reqs[name]
    local global_only, user_named = false, false
    for _, r in ipairs(rl) do
      if r.scope == "global" then global_only = true end
      if r.by == "(you)" then user_named = true end
    end
    local list = candidates(name, rl, global_only, user_named)
    if #list == 0 then
      fail(("no version of %s satisfies: %s%s"):format(name, describe(rl),
        (lookup(name) or provided[name] or (installed.global or {})[name]) and "" or " (not in the index)"), depth)
      return nil
    end

    for _, cand in ipairs(list) do
      local ch, rq, queue, ok = copy(chosen), copy(reqs), rest, true
      cand.name = name
      ch[name] = cand
      for _, d in ipairs(cand.deps) do
        -- rule 1 binds only packages we install globally now; a reused global one may be served by a local shadow
        local newly_global = cand.source == "index" and cand.scope == "global"
        local entry = { constraints = d.constraints, text = d.text, by = name, scope = newly_global and "global" or nil }
        local have = ch[d.name]
        if have then
          -- one version per name: the already chosen one must fit, and a global package needs global deps
          if not version.satisfies(have.version, d.constraints) then
            fail(("%s %s needs %s, but %s %s is already chosen (%s)"):format(name, cand.version, d.text,
              d.name, have.version, describe(rq[d.name])), depth)
            ok = false
          elseif newly_global and have.scope == "local" then
            fail(("global %s needs %s, which is only available locally"):format(name, d.name), depth)
            ok = false
          end
        else
          if provided[d.name] and not satisfies_all(provided[d.name], { entry }) then
            fail(("%s needs %s, firmware provides %s"):format(name, d.text, provided[d.name]), depth)
            ok = false
          end
          local list2 = { table.unpack(rq[d.name] or {}) }
          list2[#list2 + 1] = entry
          rq[d.name] = list2
          queue = { table.unpack(queue) }
          queue[#queue + 1] = d.name
        end
        if not ok then break end
      end
      if ok then
        local result = solve(ch, rq, queue, depth + 1)
        if result then return result end
      end
    end
    fail(("no combination satisfies %s: %s"):format(name, describe(rl)), depth, true)
    return nil
  end

  local reqs, pending = {}, {}
  for _, r in ipairs(o.requests) do
    local c, err = version.parse_constraints(r.constraint or "")
    if not c then return nil, err end
    reqs[r.name] = reqs[r.name] or {}
    table.insert(reqs[r.name], { constraints = c, text = r.name .. " " .. (r.constraint or ""),
                                 by = "(you)", scope = o.scope })
    pending[#pending + 1] = r.name
  end

  local chosen = solve({}, reqs, pending, 0)
  if not chosen then return nil, best_err or "cannot resolve" end

  -- order: dependencies first
  local order, seen = {}, {}
  local function visit(n)
    if seen[n] then return end
    seen[n] = true
    for _, d in ipairs(chosen[n].deps) do if chosen[d.name] then visit(d.name) end end
    order[#order + 1] = n
  end
  local names = {}
  for n in pairs(chosen) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do visit(n) end

  local plan = { actions = {}, breaks = {}, download = 0 }
  for _, n in ipairs(order) do
    local c = chosen[n]
    local a = { name = n, version = c.version, scope = c.scope,
                action = c.source == "index" and "install" or "reuse", size = c.size }
    if c.source == "index" then
      local g = (installed.global or {})[n]
      if c.scope == "local" and g and g.version ~= c.version then a.shadows = g.version end
      if c.scope == "global" and g and g.version ~= c.version then
        a.replaces = g.version
        for other, rec in pairs(installed.global) do      -- who would the replacement break?
          if other ~= n and not chosen[other] and rec.deps and rec.deps[n] then
            local cs = version.parse_constraints(rec.deps[n])
            if cs and not version.satisfies(c.version, cs) then
              plan.breaks[#plan.breaks + 1] = { name = n, needs = rec.deps[n], by = other }
            end
          end
        end
      end
      plan.download = plan.download + (c.size or 0)
    end
    plan.actions[#plan.actions + 1] = a
  end
  return plan
end

return M
