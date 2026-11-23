-- Builds the C modules of a rock from source on this machine (builtin-type rocks whose compiled sources are all C).
-- The index entry carries the plan (signed with everything else), vpm never evaluates a rockspec:
--   plan = { modules = { { name = "lfs", sources = {"src/lfs.c"}, defines = {...}, incdirs = {...}, libraries = {...}, libdirs = {...} } },
--            external = { OPENSSL = { header = "openssl/ssl.h", library = "ssl" } } }
-- Source: a .src.rock (zip of the rockspec and the source: loose, or as an archive) whose sha256 the index lists, checked before anything is unpacked.
-- Every value from the plan is validated and shell-quoted: the compiler is the only thing that runs, on source whose hash we checked.
local fs = require("vpm.fs")
local M = {}

-- Can vpm build this index entry? (a C rock, or one whose make/cmake step compiles nothing, with a plan and a source rock with a hash). One rule for the installer, search and the index builder.
function M.buildable(meta)
  local n = meta and meta.native
  local src = meta and meta.luarocks and meta.luarocks.src
  local kinds = { builtin = true, make = true, cmake = true }
  return n ~= nil and (n.native == "c" or n.native == "build") and kinds[n.build] == true and type(n.plan) == "table" and src ~= nil and type(src.url) == "string" and type(src.sha256) == "string"
end

function M.shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function safe_path(p) return type(p) == "string" and p ~= "" and not p:find("%z") and p:sub(1, 1) ~= "/" and not p:find("%.%.") and not p:find("\\", 1, true) end
local function safe_word(p) return type(p) == "string" and p ~= "" and not p:find("%c") end

-- plan problems are reported before any command is built
local VARNAME = "^[%a_][%w_]*$"
local function validate_vars(t, what)
  if t == nil then return true end
  if type(t) ~= "table" then return nil, "bad " .. what end
  for k, v in pairs(t) do
    if type(k) ~= "string" or not k:match(VARNAME) or type(v) ~= "string" or not safe_word(v) and v ~= "" then return nil, "bad variable in " .. what end
  end
  return true
end

-- make / cmake plans: the rockspec's own settings; every value is checked here and shell-quoted when the command is built
local function validate_script(sp, kind)
  if type(sp) ~= "table" then return nil, "bad " .. kind .. " plan" end
  for _, k in ipairs{ "makefile" } do if sp[k] ~= nil and not safe_path(sp[k]) then return nil, "bad " .. k end end
  for _, k in ipairs{ "build_target", "install_target" } do
    if sp[k] ~= nil and (type(sp[k]) ~= "string" or #sp[k] > 100 or not sp[k]:match("^[%w_%.%-/]*$")) then return nil, "bad " .. k end
  end
  for _, k in ipairs{ "build_pass", "install_pass" } do if sp[k] ~= nil and type(sp[k]) ~= "boolean" then return nil, "bad " .. k end end
  for _, k in ipairs{ "variables", "build_variables", "install_variables" } do
    local ok, err = validate_vars(sp[k], k); if not ok then return nil, err end
  end
  for pname, pt in pairs(sp.platforms or {}) do
    if type(pname) ~= "string" or type(pt) ~= "table" then return nil, "bad platforms" end
    for _, k in ipairs{ "variables", "build_variables", "install_variables" } do
      local ok, err = validate_vars(pt[k], k .. " for " .. pname); if not ok then return nil, err end
    end
  end
  for kindname, t in pairs(sp.install or {}) do
    if kindname ~= "lua" and kindname ~= "lib" then return nil, "bad install table" end
    for name, path in pairs(t) do
      if type(name) ~= "string" or not name:match("^[%w_]+[%w_%.]*$") or name:find("..", 1, true) or not safe_path(path) then return nil, "bad install entry " .. tostring(name) end
    end
  end
  return true
end

function M.validate(plan)
  if type(plan) == "table" and (plan.make ~= nil or plan.cmake ~= nil) then
    if plan.modules ~= nil or (plan.make ~= nil and plan.cmake ~= nil) then return nil, "ambiguous build plan" end
    local ok, err = validate_script(plan.make or plan.cmake, plan.make and "make" or "cmake")
    if not ok then return nil, err end
    return true
  end
  if type(plan) ~= "table" or type(plan.modules) ~= "table" or #plan.modules == 0 then return nil, "no build plan" end
  for _, m in ipairs(plan.modules) do
    if type(m.name) ~= "string" or not m.name:match("^[%w_]+[%w_%.]*$") or m.name:find("..", 1, true) then return nil, "bad module name " .. tostring(m.name) end
    if type(m.sources) ~= "table" or #m.sources == 0 then return nil, m.name .. ": no sources" end
    for _, s in ipairs(m.sources) do
      if not safe_path(s) or not s:match("%.c$") then return nil, m.name .. ": bad source " .. tostring(s) end
    end
    for _, key in ipairs{ "defines", "incdirs", "libdirs", "libraries" } do
      for _, x in ipairs(m[key] or {}) do if not safe_word(x) then return nil, m.name .. ": bad " .. key end end
    end
    for _, x in ipairs(m.libraries or {}) do if not x:match("^[%w_%.%+%-]+$") then return nil, m.name .. ": bad library " .. x end end
  end
  return true
end

-- $(NAME_INCDIR) / $(NAME_LIBDIR) as luarocks does: look for the header / library under the usual prefixes (or cfg.prefixes)
function M.locate_external(plan, prefixes, exists)
  exists = exists or fs.exists
  prefixes = prefixes or { "/usr", "/usr/local", "/opt/homebrew", "/opt/local" }
  local vars, missing = {}, {}
  for name, e in pairs(plan.external or {}) do
    local inc, lib
    for _, pre in ipairs(prefixes) do
      if not inc and e.header and exists(pre .. "/include/" .. e.header) then inc = pre .. "/include" end
      if not lib and e.library then
        for _, d in ipairs{ "/lib", "/lib64", "/lib/x86_64-linux-gnu", "/lib/aarch64-linux-gnu" } do
          for _, ext in ipairs{ ".so", ".a", ".dylib" } do
            if exists(pre .. d .. "/lib" .. e.library .. ext) then lib = lib or (pre .. d) end
          end
        end
      end
    end
    if e.header and not inc then missing[#missing + 1] = name .. " (header " .. e.header .. ")" end
    if e.library and not lib then missing[#missing + 1] = name .. " (library " .. e.library .. ")" end
    vars[name .. "_INCDIR"], vars[name .. "_LIBDIR"] = inc, lib
  end
  return vars, missing
end

local function subst(x, vars)
  return (x:gsub("%$%(([%w_]+)%)", function(n) return vars[n] or "" end))
end

-- the command line for one module; root = unpacked source, out = file to write
function M.command(profile, hdrdir, m, root, out, vars)
  vars = vars or {}
  local flags = profile.platform == "macos" and "-bundle -undefined dynamic_lookup" or "-shared -fPIC"
  local parts = { M.shq(profile.cc), "-O2", flags, "-I" .. M.shq(hdrdir) }
  for _, d in ipairs(m.incdirs or {}) do
    d = subst(d, vars)
    if d ~= "" then parts[#parts + 1] = "-I" .. M.shq(d:sub(1, 1) == "/" and d or (root .. "/" .. d)) end
  end
  for _, d in ipairs(m.defines or {}) do parts[#parts + 1] = "-D" .. M.shq(d) end
  for _, s in ipairs(m.sources) do parts[#parts + 1] = M.shq(root .. "/" .. s) end
  for _, d in ipairs(m.libdirs or {}) do
    d = subst(d, vars)
    if d ~= "" then parts[#parts + 1] = "-L" .. M.shq(d) end
  end
  for _, l in ipairs(m.libraries or {}) do parts[#parts + 1] = "-l" .. M.shq(l) end
  parts[#parts + 1] = "-o " .. M.shq(out)
  return table.concat(parts, " ")
end

-- compile every module of the plan into destdir (module "a.b" -> destdir/a/b.so); returns the list of files, or nil, message
-- platform names a rockspec may use for this machine, most general first
local function platform_names(profile)
  local p = profile.platform
  if p == "linux" then return { "unix", "linux" } end
  if p == "macos" or p == "macosx" or p == "darwin" then return { "unix", "macosx" } end
  if p == "windows" then return { "windows", "mingw32" } end
  return { "unix", tostring(p) }
end

-- one variable table as the rockspec means it for this machine: common `variables`, then the kind's own, then platform overrides of both
local function merged(sp, key, profile)
  local t = {}
  local function add(src) for k, v in pairs(src or {}) do t[k] = v end end
  add(sp.variables); add(sp[key])
  for _, pn in ipairs(platform_names(profile)) do
    local pt = (sp.platforms or {})[pn]
    if pt then add(pt.variables); add(pt[key]) end
  end
  return t
end

local function sorted_keys(t) local k = {} for n in pairs(t) do k[#k + 1] = n end table.sort(k) return k end

-- A make or cmake rock: run its own build scripts on the unpacked source. Third-party scripts can run anything, so by default this needs a sandbox
-- (bubblewrap: no network, read-only system, only the work folder writable); without one it needs opts.allow_scripts (the user said so).
-- Everything the rock installs into the flat library folder (LIBDIR = LUADIR = out) becomes the package's files; PREFIX, BINDIR and CONFDIR are scratch.
local function build_script(profile, plan, root, destdir, opts)
  local run = opts.run or function(cmd) local r = os.execute(cmd); return r == 0 or r == true end
  local kind = plan.make and "make" or "cmake"
  local sp = plan[kind]
  if not profile.cc then return nil, "no C compiler" end
  local mk = profile.make
  for _, t in ipairs(require("vpm.profile").plan_tools(plan)) do
    if t == "make" and not mk then return nil, "make is not installed" end
    if t == "cmake" and not (profile.tools or {}).cmake then return nil, "cmake is not installed" end
  end
  local sandbox = profile.sandbox == "bwrap"
  if not sandbox and not opts.allow_scripts then
    return nil, ("this rock runs its own %s build scripts and no sandbox is available here: repeat with --allow-scripts if you trust it"):format(kind)
  end
  local vars, missing = M.locate_external(plan, opts.prefixes, opts.exists)
  if #missing > 0 then return nil, "missing system libraries: " .. table.concat(missing, ", ") end

  local work = destdir .. "/.vpm-work"
  local out, prefix, hdr = work .. "/out", work .. "/prefix", work .. "/headers"
  for _, d in ipairs{ out, prefix .. "/bin", prefix .. "/etc", hdr .. "/lib" } do fs.mkdirp(d) end
  local okh, herr = require("vapor.luaheaders").write(hdr)
  if not okh then return nil, "cannot write Lua headers: " .. tostring(herr) end
  local function cleanup() fs.rmtree(work) end

  local libflag = (profile.platform == "macos" or profile.platform == "macosx") and "-bundle -undefined dynamic_lookup" or "-shared"
  local v = {
    PREFIX = prefix, BINDIR = prefix .. "/bin", CONFDIR = prefix .. "/etc", LIBDIR = out, LUADIR = out,
    LUA_INCDIR = hdr, LUA_LIBDIR = hdr .. "/lib", LUA_BINDIR = prefix .. "/bin", LUA = opts.lua or "lua", LUALIB = "", LUA_VERSION = "5.4",
    LIB_EXTENSION = "so", OBJ_EXTENSION = "o", CC = profile.cc, LD = profile.cc,
    CFLAGS = "-O2 -fPIC -I" .. hdr, LIBFLAG = libflag,
  }
  for k, x in pairs(vars) do v[k] = x end

  local function expand(t)
    local r = {}
    for _, k in ipairs(sorted_keys(t)) do r[#r + 1] = M.shq(k .. "=" .. subst(t[k], v)) end
    return table.concat(r, " ")
  end

  -- one step: in the source folder, inside the sandbox when there is one
  local log = work .. "/build.log"
  local function step(argv_text)
    local inner = "cd " .. M.shq(root) .. " && " .. argv_text
    if sandbox then
      local b = { "bwrap --unshare-all --die-with-parent --new-session --clearenv --setenv HOME /tmp --setenv PATH /usr/bin:/bin --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/bin /bin --ro-bind-try /etc/alternatives /etc/alternatives --tmpfs /tmp" }
      for _, pfx in ipairs(opts.prefixes or {}) do if pfx:sub(1, 5) ~= "/usr" then b[#b + 1] = "--ro-bind-try " .. M.shq(pfx) .. " " .. M.shq(pfx) end end
      b[#b + 1] = "--bind " .. M.shq(work) .. " " .. M.shq(work) .. " --bind " .. M.shq(root) .. " " .. M.shq(root) .. " --proc /proc --dev /dev --chdir " .. M.shq(root) .. " sh -c " .. M.shq(inner)
      inner = table.concat(b, " ")
    end
    return run(inner .. " >> " .. M.shq(log) .. " 2>&1")
  end
  local function fail(what)
    local f = io.open(log, "rb")
    local text = f and f:read("a") or ""
    if f then f:close() end
    cleanup()
    return nil, ("%s failed:\n%s"):format(what, text:sub(-1500))
  end

  if kind == "make" then
    local mf = M.shq(sp.makefile or "Makefile")
    if sp.build_pass ~= false then
      local cmd = ("%s -f %s %s %s"):format(M.shq(mk), mf, M.shq(sp.build_target or ""), expand(merged(sp, "build_variables", profile)))
      if not step((cmd:gsub(" '' ", " "))) then return fail("make") end
    end
    if sp.install_pass ~= false then
      local cmd = ("%s -f %s %s %s"):format(M.shq(mk), mf, M.shq(sp.install_target or "install"), expand(merged(sp, "install_variables", profile)))
      if not step(cmd) then return fail("make install") end
    end
    -- files the rockspec lists to install from the source tree
    for _, kindname in ipairs{ "lua", "lib" } do
      for name, path in pairs((sp.install or {})[kindname] or {}) do
        local dest = out .. "/" .. name:gsub("%.", "/") .. (kindname == "lua" and ".lua" or ".so")
        local src = root .. "/" .. path
        if not run(("test -f %s && test ! -L %s"):format(M.shq(src), M.shq(src))) then return fail("copying " .. path .. " (not a regular file in the build tree)") end
        fs.mkdirp(dest:match("^(.*)/[^/]*$"))
        if not run(("cp %s %s"):format(M.shq(src), M.shq(dest))) then return fail("copying " .. path) end
      end
    end
  else
    local cvars = merged(sp, "variables", profile)
    if cvars.CMAKE_INSTALL_PREFIX == nil then cvars.CMAKE_INSTALL_PREFIX = "$(PREFIX)" end
    if cvars.CMAKE_BUILD_TYPE == nil then cvars.CMAKE_BUILD_TYPE = "Release" end
    local d = {}
    for _, k in ipairs(sorted_keys(cvars)) do d[#d + 1] = M.shq("-D" .. k .. "=" .. subst(cvars[k], v)) end
    local build = M.shq(work .. "/cmake-build")
    if not step(("cmake -S . -B %s %s"):format(build, table.concat(d, " "))) then return fail("cmake configure") end
    if not step(("cmake --build %s --config Release"):format(build)) then return fail("cmake build") end
    if not step(("cmake --build %s --target install --config Release"):format(build)) then return fail("cmake install") end
  end

  -- what to install: the flat library folder; a rock that installed into PREFIX's lua tree (lib/lua/5.x, share/lua/5.x) is relocated from there
  local function files_under(dir)
    local list, p = {}, io.popen(("cd %s && find . -type f 2>/dev/null"):format(M.shq(dir)))
    for l in p:lines() do list[#list + 1] = l:gsub("^%./", "") end
    p:close()
    return list
  end
  local links = io.popen(("find %s ! -type f ! -type d 2>/dev/null | head -1"):format(M.shq(out)))
  local link = links:read("l"); links:close()
  if link then return fail("the build installed a link or special file (" .. link .. ")") end
  local result, seen = {}, {}
  for _, rel in ipairs(files_under(out)) do
    if not safe_path(rel) then return fail("unsafe installed path " .. rel) end
    result[#result + 1] = rel; seen[rel] = out .. "/" .. rel
  end
  if #result == 0 then
    for _, rel in ipairs(files_under(prefix)) do
      local dest = rel:match("lib/lua/[%d%.]+/(.+)$") or rel:match("share/lua/[%d%.]+/(.+)$")
      if dest and safe_path(dest) and (dest:match("%.so$") or dest:match("%.lua$")) then result[#result + 1] = dest; seen[dest] = prefix .. "/" .. rel end
    end
  end
  if #result == 0 then return fail("the build produced no files vpm can install (nothing in LIBDIR/LUADIR)") end
  table.sort(result)
  for _, rel in ipairs(result) do
    local target = destdir .. "/" .. rel
    fs.mkdirp(target:match("^(.*)/[^/]*$"))
    if not run(("cp %s %s"):format(M.shq(seen[rel]), M.shq(target))) then return fail("copying " .. rel) end
  end
  cleanup()
  return result
end

function M.build(profile, plan, root, destdir, opts)
  opts = opts or {}
  local run = opts.run or function(cmd) local r = os.execute(cmd); return r == 0 or r == true end
  local ok, err = M.validate(plan)
  if not ok then return nil, err end
  if plan.make or plan.cmake then return build_script(profile, plan, root, destdir, opts) end
  if not profile.cc then return nil, "no C compiler" end
  local vars, missing = M.locate_external(plan, opts.prefixes, opts.exists)
  if #missing > 0 then return nil, "missing system libraries: " .. table.concat(missing, ", ") end

  local hdr = destdir .. "/.vpm-build-headers"
  fs.mkdirp(hdr)
  local okh, herr = require("vapor.luaheaders").write(hdr)
  if not okh then return nil, "cannot write Lua headers: " .. tostring(herr) end

  local built = {}
  for _, m in ipairs(plan.modules) do
    local rel = m.name:gsub("%.", "/") .. ".so"
    local out = destdir .. "/" .. rel
    fs.mkdirp(out:match("^(.*)/[^/]*$"))
    local log = hdr .. "/build.log"
    local cmd = M.command(profile, hdr, m, root, out, vars) .. " > " .. M.shq(log) .. " 2>&1"
    if not run(cmd) then
      local f = io.open(log, "rb")
      local text = f and f:read("a") or ""
      if f then f:close() end
      for _, b in ipairs(built) do fs.remove(destdir .. "/" .. b) end
      fs.rmtree(hdr)
      return nil, ("building %s failed:\n%s"):format(m.name, text:sub(-1500))
    end
    built[#built + 1] = rel
  end
  fs.rmtree(hdr)
  return built
end

-- Unpack a .src.rock (or a plain archive) into dir and return the source root. Same rules as the index builder: the zip holds either a loose source tree or the
-- original archive; `srcdir` (rockspec source.dir) names the directory when it is not the only one.
function M.unpack(profile, file, dir, srcdir, run)
  run = run or function(cmd) local r = os.execute(cmd); return r == 0 or r == true end
  local z, x = dir .. "/z", dir .. "/x"
  fs.mkdirp(z); fs.mkdirp(x)
  local function sh(cmd) return run(cmd) end
  local head = io.open(file, "rb"); local magic = head and head:read(4) or ""; if head then head:close() end
  local is_zip = magic:sub(1, 2) == "PK"
  if is_zip then
    if not profile.tools.unzip then return nil, "unzip is needed to unpack this" end
    if not sh("unzip -q -o " .. M.shq(file) .. " -d " .. M.shq(z)) then return nil, "cannot unpack the source rock" end
  else
    if not profile.tools.tar then return nil, "tar is needed to unpack this" end
    if not sh(("tar -xf %s -C %s --no-same-owner --no-same-permissions"):format(M.shq(file), M.shq(x))) then return nil, "cannot unpack the source archive" end
  end
  if is_zip then
    local p = io.popen("ls -A " .. M.shq(z))
    local names = {}
    for n in p:lines() do names[#names + 1] = n end
    p:close()
    for _, f in ipairs(names) do
      local full = z .. "/" .. f
      if f:match("%.zip$") then
        if not profile.tools.unzip or not sh(("unzip -q -o %s -d %s"):format(M.shq(full), M.shq(x))) then return nil, "cannot unpack the source" end
      elseif f:match("%.tar") or f:match("%.tgz$") or f:match("%.tbz2?$") then
        if not profile.tools.tar or not sh(("tar -xf %s -C %s --no-same-owner --no-same-permissions"):format(M.shq(full), M.shq(x))) then return nil, "cannot unpack the source" end
      elseif not f:match("%.rockspec$") then
        sh(("mv %s %s"):format(M.shq(full), M.shq(x .. "/" .. f)))
      end
    end
  end
  if srcdir and safe_path(srcdir) and fs.exists(x .. "/" .. srcdir) then return x .. "/" .. srcdir end
  local p = io.popen("ls -A " .. M.shq(x))
  local names = {}
  for n in p:lines() do names[#names + 1] = n end
  p:close()
  if #names == 1 and fs.exists(x .. "/" .. names[1] .. "/.") then return x .. "/" .. names[1] end
  return x
end

return M
