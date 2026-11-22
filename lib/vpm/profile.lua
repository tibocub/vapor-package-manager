-- What this machine can do, for filtering and for "can I install this?": runtime, compiler, tools. Detected once per run.
--   profile.detect([env]) -> { platform, dialect, dlopen, exec, cc, tools = { tar=, unzip= }, can_build_c, missing = { ... } }
-- env (tests): { vapor = <table>, run = function(cmd) -> boolean, getenv = function(name) }
local M = {}

local function default_run(cmd)
  local r = os.execute(cmd)
  return r == 0 or r == true       -- 5.1 returns the status, 5.4 returns true
end

function M.detect(env)
  env = env or {}
  local v = env.vapor or vapor or {}
  local run = env.run or default_run
  local getenv = env.getenv or os.getenv
  local caps = v.caps or {}
  local p = { platform = v.platform, dialect = v.dialect, dlopen = caps.dlopen and true or false, exec = caps.exec and true or false, tools = {}, missing = {} }

  if p.exec then
    local function have(tool) return run("command -v " .. tool .. " >/dev/null 2>&1") end
    local cc = getenv("CC")
    if cc and cc:match("^[%w_%./%-]+$") and have(cc) then p.cc = cc
    else for _, c in ipairs{ "cc", "gcc", "clang" } do if have(c) then p.cc = c; break end end end
    for _, t in ipairs{ "tar", "unzip" } do if have(t) then p.tools[t] = true end end
  end

  if not p.exec then p.missing[#p.missing + 1] = "a way to run programs"
  else
    if not p.dlopen then p.missing[#p.missing + 1] = "a runtime that loads .so files (dlopen)" end
    if not p.cc then p.missing[#p.missing + 1] = "a C compiler" end
    if not p.tools.tar then p.missing[#p.missing + 1] = "tar" end
    if not p.tools.unzip then p.missing[#p.missing + 1] = "unzip" end
  end
  p.can_build_c = #p.missing == 0
  return p
end

-- can this machine install a package of this native class? (pure always; "c" when it can build C; build/other: not yet)
function M.can_install(p, class)
  if class == nil or class == false or class == "pure" then return true end
  if class == "c" then return p.can_build_c, p.missing end
  return false, { "a build for this kind of rock (not supported yet)" }
end

return M
