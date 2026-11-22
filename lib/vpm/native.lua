-- Builds the C modules of a rock from source on this machine (builtin-type rocks whose compiled sources are all C).
-- The index entry carries the plan (signed with everything else), vpm never evaluates a rockspec:
--   plan = { modules = { { name = "lfs", sources = {"src/lfs.c"}, defines = {...}, incdirs = {...}, libraries = {...}, libdirs = {...} } },
--            external = { OPENSSL = { header = "openssl/ssl.h", library = "ssl" } } }
-- Source: a .src.rock (zip of the rockspec and the source: loose, or as an archive) whose sha256 the index lists, checked before anything is unpacked.
-- Every value from the plan is validated and shell-quoted: the compiler is the only thing that runs, on source whose hash we checked.
local fs = require("vpm.fs")
local M = {}

-- Can vpm build this index entry? (a C rock with the builtin build type, a plan, and a source rock with a hash). One rule for the installer, search and the index builder.
function M.buildable(meta)
  local n = meta and meta.native
  local src = meta and meta.luarocks and meta.luarocks.src
  return n ~= nil and n.native == "c" and n.build == "builtin" and type(n.plan) == "table" and src ~= nil and type(src.url) == "string" and type(src.sha256) == "string"
end

function M.shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function safe_path(p) return type(p) == "string" and p ~= "" and not p:find("%z") and p:sub(1, 1) ~= "/" and not p:find("%.%.") and not p:find("\\", 1, true) end
local function safe_word(p) return type(p) == "string" and p ~= "" and not p:find("%c") end

-- plan problems are reported before any command is built
function M.validate(plan)
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
function M.build(profile, plan, root, destdir, opts)
  opts = opts or {}
  local run = opts.run or function(cmd) local r = os.execute(cmd); return r == 0 or r == true end
  local ok, err = M.validate(plan)
  if not ok then return nil, err end
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
