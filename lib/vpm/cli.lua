-- Command line front end: parse arguments, build the context, dispatch to lib/vpm/cmd/<name>.lua (loaded on
-- demand so a command only pays RAM for the code it uses). docs/spec.md is the reference.
--
--   main(argv, env) -> exit code
--   env (all optional, for tests): out(s), err(s), read() -> line, config (table), decode, cwd, now
-- Exit codes: 0 ok, 1 error, 2 usage, 3 unresolvable, 4 network or integrity failure.
local M = {}

local ALIASES = { i = "install", rm = "remove", ls = "list", u = "upgrade" }
local COMMANDS = { install = true, remove = true, list = true, upgrade = true, why = true, info = true,
                   check = true, world = true, init = true, search = true }
local FLAGS = { g = "global", n = "dry_run", y = "yes", q = "quiet", v = "verbose", f = "force" }
local LONG = { global = "global", ["dry-run"] = "dry_run", yes = "yes", quiet = "quiet", verbose = "verbose",
               force = "force", repair = "repair", ["no-register"] = "no_register",
               pure = "pure", works = "works", ["no-host"] = "no_host", all = "all" }

local USAGE = [[
usage: vpm <command> [options] [packages]
  install (i) [pkg[@ver]...]   install packages, or what ./vpm.lua asks for
  remove (rm) pkg...           remove packages
  list (ls)                    list installed packages
  upgrade (u) [pkg...]         upgrade to the newest allowed versions
  why pkg                      what uses a package
  info pkg                     versions, dependencies, size
  search [words]               find packages: --pure  --native=none|c|any  --host=nvim,love  --no-host  --works (runs on vlr)  --all
  check [--repair]             verify installed files, undo a crashed run
  world                        the packages you asked for
  init                         create a vpm.lua here
options: -g global   -n dry run   -y no questions   --deps=auto|global|local   --index=URL   -f/--force   -v   -q]]

-- returns { cmd=, args={}, flags={} } or nil, message
function M.parse(argv)
  local r = { args = {}, flags = {} }
  for _, a in ipairs(argv) do
    local long, val = a:match("^%-%-([%w%-]+)=?(.*)$")
    if long and a:sub(1, 2) == "--" then
      if LONG[long] then r.flags[LONG[long]] = true
      elseif long == "deps" or long == "index" or long == "config" or long == "native" or long == "host" then
        if val == "" then return nil, "--" .. long .. " needs a value (--" .. long .. "=...)" end
        r.flags[long] = val
      else return nil, "unknown option --" .. long end
    elseif a:match("^%-%a+$") then
      for c in a:sub(2):gmatch(".") do
        if not FLAGS[c] then return nil, "unknown option -" .. c end
        r.flags[FLAGS[c]] = true
      end
    elseif not r.cmd then r.cmd = ALIASES[a] or a
    else r.args[#r.args + 1] = a end
  end
  if r.flags.deps and not ({ auto = 1, global = 1, ["local"] = 1 })[r.flags.deps] then
    return nil, "--deps must be auto, global or local"
  end
  return r
end

local function size(n)
  if not n then return "?" end
  n = math.floor(n)                       -- cjson hands back floats
  if n < 1024 then return n .. " B" end
  return ("%.0f KB"):format(n / 1024)
end
M.size = size

-- Context handed to every command.
local function context(parsed, env)
  local ctx = { flags = parsed.flags, env = env }
  local out = env.out or function(s) io.write(s) end
  local err = env.err or function(s) io.stderr:write(s) end
  function ctx.out(fmt, ...) if not parsed.flags.quiet then out(select("#", ...) > 0 and fmt:format(...) or fmt) out("\n") end end
  function ctx.err(fmt, ...) err("vpm: " .. (select("#", ...) > 0 and fmt:format(...) or fmt) .. "\n") end
  function ctx.ask(prompt)
    out(prompt .. " [Y/n] ")
    local line = (env.read or io.read)()
    if line == nil then return nil end          -- no terminal
    line = line:lower():match("^%s*(.-)%s*$")
    return line == "" or line == "y" or line == "yes"
  end
  ctx.scope = parsed.flags.global and "global" or "local"
  local okl, lfs = pcall(require, "lfs")
  ctx.cwd = env.cwd or (okl and lfs.currentdir()) or os.getenv("PWD") or "."
  ctx.size = size

  local cfg = env.config
  if not cfg then
    local path = parsed.flags.config or os.getenv("VPM_CONFIG")
    local f = path and io.open(path, "rb")
    for _, p in ipairs(path and {} or { "/flash/etc/vpm.lua", "/etc/vpm.lua" }) do
      path = p; f = io.open(p, "rb"); if f then break end
    end
    if not f then return nil, "no configuration file (looked for " .. tostring(path) .. "; set VPM_CONFIG or use --config=)" end
    local chunk = load(f:read("a"), "=" .. path, "t", {})
    f:close()
    local ok, t = pcall(chunk or error, "bad config")
    if not ok or type(t) ~= "table" then return nil, "bad configuration file " .. path end
    cfg = t
  end
  cfg = setmetatable({}, { __index = cfg })
  cfg.index = parsed.flags.index or cfg.index
  cfg.local_root = cfg.local_root or (ctx.cwd .. "/lua_modules")
  ctx.cfg = cfg

  -- Lazily built services; each command loads only what it uses (RAM is the scarce resource, docs/ram-budget.md).
  local built = {}
  function ctx.index()
    if not built.index then
      local transport = env.transport or require("vpm.transport")
      local decode = env.decode or (function() local ok, c = pcall(require, "cjson"); return ok and c.decode end)()
      if not decode then error("no JSON decoder available") end
      transport.cafile = cfg.cafile               -- trusted roots for https
      built.transport = transport
      local keys
      for i, hex in ipairs(cfg.keys or {}) do
        keys = keys or {}
        keys[i] = (hex:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
      end
      built.index = require("vpm.index").new{ base = cfg.index or error("no index configured"), transport = transport, decode = decode,
        keys = keys, verify = env.verify, serial_file = keys and (cfg.libdir .. "/.vpm/index-serial"), hosts = cfg.hosts }
    end
    return built.index
  end
  function ctx.installer()          -- downloads and places files: load it after resolving, not before
    if not built.installer then
      local index = ctx.index()
      built.installer = require("vpm.installer").new{ cfg = cfg, transport = built.transport, index = index, now = env.now }
    end
    return built.installer
  end
  function ctx.maintainer()         -- remove, check, repair: no network code
    if not built.maintainer then built.maintainer = require("vpm.maintain").new{ cfg = cfg, now = env.now } end
    return built.maintainer
  end
  -- unload modules that are no longer needed (the resolver while downloading) and collect
  function ctx.release(...)
    for _, n in ipairs{ ... } do package.loaded[n] = nil end
    collectgarbage()
  end
  function ctx.state(scope)
    return require("vpm.state").open(scope == "global" and cfg.libdir or cfg.local_root)
  end
  function ctx.provided()
    if cfg.provided then return cfg.provided end
    if built.provided == nil then
      local index = ctx.index()
      local meta, _, merr = index:meta()
      if not meta and index.keys then error(merr or "cannot read the index metadata") end
      built.provided = meta and meta.provided or {}
    end
    return built.provided
  end
  return ctx
end

function M.main(argv, env)
  env = env or {}
  local parsed, perr = M.parse(argv)
  if not parsed then (env.err or function(x) io.stderr:write(x) end)("vpm: " .. perr .. "\n"); return 2 end
  if not parsed.cmd or parsed.cmd == "help" then
    (env.out or io.write)(USAGE .. "\n"); return parsed.cmd and 0 or 2
  end
  if not COMMANDS[parsed.cmd] then
    (env.err or function(s) io.stderr:write(s) end)("vpm: unknown command '" .. parsed.cmd .. "' (try: vpm help)\n")
    return 2
  end
  local ctx, cerr = context(parsed, env)
  if not ctx then (env.err or function(s) io.stderr:write(s) end)("vpm: " .. cerr .. "\n"); return 1 end
  local ok, code = pcall(require("vpm.cmd." .. parsed.cmd), ctx, parsed.args)
  if not ok then ctx.err("%s", tostring(code)); return 1 end
  return code or 0
end

return M
