-- Work out what a rock installs and check it, given its evaluated rockspec and fetched source tree.
-- analyze(rs, srcroot, origin) -> entry | nil, reason
-- Follows luarocks/build/builtin.lua for the destination of each file (including its init.lua rule and the
-- src/lua/lib auto-detection when `build.modules` is absent).
local source = require("source")
local q, run = source.q, source.run

local M = {}

local MAX_FILE = tonumber(os.getenv and os.getenv("VLR_MAX_FILE")) or 512000   -- bytes per file (env VLR_MAX_FILE); bigger is data, not a library for a 187 KB device, and the index host mirrors blobs

local STDLIB = { string = 1, table = 1, math = 1, os = 1, io = 1, coroutine = 1, utf8 = 1, debug = 1,
                 package = 1, bit32 = 1, jit = 1, ffi = 1 }

local function module_path(name) return (name:gsub("%.", "/")) end

local function list(dir, pattern)
  local ok, out = run(("cd %s && find . -type f -name %s -not -path './.git/*' | sort"):format(q(dir), q(pattern)))
  local t = {}
  if ok then for f in out:gmatch("[^\n]+") do t[#t + 1] = f:gsub("^%./", "") end end
  return t
end

-- dest (install path relative to the library dir) -> source path (relative to the source root)
local function plan(rs, root, opts)
  local build = rs.build or {}
  local files, bin = {}, {}
  local modules = build.modules
  if build.type == "none" then modules = nil end

  if build.type ~= "none" and modules == nil then      -- builtin auto-detection
    local prefix = ""
    for _, p in ipairs({ "src", "lua", "lib" }) do
      if run("test -d " .. q(root .. "/" .. p)) then prefix = p .. "/"; break end
    end
    local base = prefix == "" and root or (root .. "/" .. prefix)
    if #list(base, "*.c") > 0 then return nil, "native-source" end
    modules = {}
    for _, f in ipairs(list(base, "*.lua")) do
      local top = f:match("^([^/]*)")
      if top ~= "spec" and top ~= ".luarocks" and top ~= "lua_modules" and f ~= "test.lua" and f ~= "tests.lua" then
        modules[(f:gsub("%.lua$", ""):gsub("/", "."))] = prefix .. f
      end
    end
  end

  for name, src in pairs(modules or {}) do
    if type(src) == "table" then src = src.sources and (type(src.sources) == "string" and src.sources or src.sources[1]) or src[1] end
    local ext = type(src) == "string" and src:match("%.([^.]+)$")
    if ext ~= "lua" and not (opts and opts.skip_native) then return nil, "native-source" end
    if ext == "lua" then
      local moddir = module_path(name)
      if src:match("[^/]*$") == "init.lua" and not name:match("%.init$") then
        files[moddir .. "/init.lua"] = src
      else
        local basename = name:match("([^.]+)$")
        files[(moddir:match("^(.*)/[^/]*$") and (moddir:match("^(.*)/[^/]*$") .. "/") or "") .. basename .. ".lua"] = src
      end
    end
  end

  local install = build.install or {}
  local NATIVE_EXT = { c = true, h = true, cc = true, cpp = true, cxx = true, so = true, dll = true, dylib = true, o = true, a = true, rs = true, go = true }
  for name, src in pairs(install.lua or {}) do
    if type(src) ~= "string" or NATIVE_EXT[src:match("%.([%w_]+)$") or ""] then return nil, "native-source" end
    if type(name) == "number" then files[src] = src          -- a list: installed under the same relative path (also data files such as Teal .d.tl)
    elseif src:match("%.lua$") then files[module_path(tostring(name)) .. ".lua"] = src
    else files[module_path(tostring(name)) .. "." .. src:match("%.([%w_]+)$")] = src end
  end
  local binlist = install.bin or {}
  for k, src in pairs(binlist) do
    if type(src) == "string" then bin[type(k) == "string" and k or src:match("[^/]*$")] = src end
  end
  return files, bin
end

-- literal require() calls; comments are not stripped (this only produces warnings)
local function requires_in(text, set)
  for m in text:gmatch("require%s*%(?%s*[\"']([%w_%.%-]+)[\"']") do set[m] = true end
end

function M.analyze(rs, root, origin, opts)
  local files, bin = plan(rs, root, opts)
  if not files then return nil, bin end            -- bin holds the reason here

  local entry = { files = {}, bin = {}, modules = {}, requires = {} }
  local reqset, paths = {}, {}
  local all = {}
  for dest, src in pairs(files) do all[#all + 1] = { dest = dest, src = src } end
  for name, src in pairs(bin) do all[#all + 1] = { bin = name, src = src, dest = "bin/" .. name } end
  table.sort(all, function(a, b) return a.dest < b.dest end)

  for _, f in ipairs(all) do
    if f.src:find("..", 1, true) or f.src:sub(1, 1) == "/" then return nil, "unsafe-path" end
    local full = root .. "/" .. f.src
    if not run("test -f " .. q(full) .. " -a ! -L " .. q(full)) then return nil, "missing-file:" .. f.src end
    local h = io.open(full, "rb")
    local text = h:read("a"); h:close()
    if #text > MAX_FILE then return nil, "file-too-large" end
    local body = text:gsub("^#[^\n]*", "")
    local islua = f.src:match("%.lua$") or f.bin
    if islua then
      local fn, err = load(body, "=" .. f.src, "t")
      if not fn then return nil, "syntax-5.4" end
      requires_in(body, reqset)
    end
    if not f.bin and islua then entry.modules[#entry.modules + 1] = (f.dest:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")) end
    paths[#paths + 1] = f
    entry.size = (entry.size or 0) + #text
  end

  if #paths > 0 then
    local args = {}
    for _, f in ipairs(paths) do args[#args + 1] = q(root .. "/" .. f.src) end
    local ok, out = run("sha256sum " .. table.concat(args, " "))
    if not ok then return nil, "hash-failed" end
    local hashes = {}
    for h, p in out:gmatch("(%x+)  ([^\n]+)") do hashes[p] = h end
    for _, f in ipairs(paths) do
      local ent = { sha256 = hashes[root .. "/" .. f.src], src = f.src }
      local fh = io.open(root .. "/" .. f.src, "rb"); ent.size = fh:seek("end"); fh:close()
      if f.bin then entry.bin[f.bin] = f.dest end
      entry.files[f.dest] = ent
    end
  end

  -- requires that are not our own modules, the standard library or something obviously unrelated
  local own = {}
  for _, m in ipairs(entry.modules) do own[m] = true end
  for m in pairs(reqset) do
    local root_name = m:match("^[^.]+")
    if not own[m] and not own[root_name] and not STDLIB[m] and not STDLIB[root_name] then entry.requires[#entry.requires + 1] = m end
  end
  table.sort(entry.requires); table.sort(entry.modules)
  if reqset.ffi or reqset.jit then entry.luajit = true end
  return entry
end

return M
