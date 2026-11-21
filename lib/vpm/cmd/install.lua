-- vpm install [pkg[@ver]...] : resolve, show the plan, ask when it does more than asked, apply.
local plan_ui = require("vpm.plan")
local fs = require("vpm.fs")

local function is_dir_spec(s) return s:match("^%.%.?/") or s:match("^/") or s:match("^file://") or s == "." or s == ".." end

local function spec(s)
  local name, c = s:match("^([^@]+)@(.+)$")
  if not name then name, c = s, "" end
  if not name:match("^[%w][%w%._%-]*$") then return nil, "bad package name '" .. name .. "'" end
  if c ~= "" and not c:match("^[<>=~!]") then c = "~> " .. c end     -- name@1.2 : LuaRocks prefix match
  return { name = name, constraint = c }
end

local function read_manifest(ctx)
  local f = io.open(ctx.cwd .. "/vpm.lua", "rb")
  if not f then return nil end
  local chunk = load(f:read("a"), "=vpm.lua", "t", {})
  f:close()
  local ok, t = pcall(chunk or error, "bad")
  return ok and type(t) == "table" and t or nil
end

return function(ctx, args)
  local requests, requested, fresh = {}, {}, {}
  if #args == 0 then
    local m = read_manifest(ctx)
    if not m or not next(m.deps or {}) then
      ctx.err("nothing to install: name a package, or run in a directory whose vpm.lua lists deps")
      return 2
    end
    local names = {}
    for n in pairs(m.deps) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do requests[#requests + 1] = { name = n, constraint = m.deps[n] }; requested[n] = m.deps[n] end
  else
    for _, a in ipairs(args) do
      if is_dir_spec(a) then
        local dir = a:gsub("^file://", "")
        if dir:sub(1, 1) ~= "/" then dir = ctx.cwd .. "/" .. dir:gsub("^%./", "") end
        local doc, derr = require("vpm.localsrc").load(dir)
        if not doc then ctx.err("%s", derr); return 1 end
        ctx.index():add_local(doc)
        local version = next(doc.versions)
        requests[#requests + 1] = { name = doc.name, constraint = "== " .. version }
        requested[doc.name] = ""
        fresh[doc.name] = true
        goto continue
      end
      local r, err = spec(a)
      if not r then ctx.err("%s", err); return 2 end
      requests[#requests + 1] = r
      requested[r.name] = r.constraint
      ::continue::
    end
  end

  local index = ctx.index()
  local plan, err = require("vpm.resolver").resolve{
    requests = requests, fresh = fresh, scope = ctx.scope, deps = ctx.flags.deps or ctx.cfg.deps or "auto",
    provided = ctx.provided(),
    installed = { global = ctx.state("global"):installed_view(), ["local"] = ctx.state("local"):installed_view() },
    index = function(n) return index:resolver_view(n) end,
  }
  if index.failed then ctx.err("%s", index.failed); return 4 end -- integrity and network failures are never "unresolvable"
  if not plan then
    for name, host in pairs(index.hidden or {}) do
      ctx.err("%s is written for %s and is not offered here (add hosts = { \"%s\" } to the vpm config if this runtime provides it)", name, host, host)
    end
    ctx.err("%s", err); return 3
  end

  local installs = plan_ui.installs(plan)
  plan_ui.show(ctx, plan)
  if ctx.flags.dry_run then return 0 end
  if installs > 0 and (plan_ui.needs_prompt(plan, requested, ctx.scope)) and not ctx.flags.yes then
    ctx.out("Download: %s", ctx.size(plan.download))
    local yes = ctx.ask("Continue?")
    if yes == nil then ctx.err("this needs confirmation and there is no terminal: use -y"); return 1 end
    if not yes then ctx.out("aborted"); return 1 end
  end

  ctx.release("vpm.resolver", "vpm.version")          -- not needed while downloading
  local ok, aerr, code = ctx.installer():apply(plan, requested)
  if not ok then ctx.err("%s", aerr); return code or 1 end
  ctx.out(installs == 0 and "nothing to install, everything is already there" or "installed %d package(s)", installs)

  if ctx.scope == "local" then
    if fs.exists(ctx.cwd .. "/vpm.lua") then
      local resolved = {}
      for _, a in ipairs(plan.actions) do resolved[a.name] = { version = a.version, scope = a.scope } end
      fs.write(ctx.cwd .. "/vpm-lock.lua", require("vpm.state").serialise({ resolved = resolved }))
    end
    if not ctx.flags.no_register and ctx.cfg.libdir then
      local gs = ctx.state("global")
      local projects = gs:projects()
      if not projects[ctx.cwd] then projects[ctx.cwd] = true; gs:set_projects(projects) end
    end
  end
  return 0
end
