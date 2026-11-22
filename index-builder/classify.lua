-- Native-code classifier: what does building this rock need? (docs/native-detection.md)
--   classify(rs [, tree]) -> { native = false }                                    pure Lua: copying files is the whole install
--                         |  { native = "c",     langs = {"c"}, ... }                only C: a C compiler (and headers of `external`) is enough
--                         |  { native = "build", build = "make" }                      a build step (make, command, a build backend) but no compiled code in the tree: needs the tool, not a compiler
--                         |  { native = "other", langs = {"c++","rust",...}, ... }   anything else (C++, Rust, Go, a Makefile whose language we cannot tell, prebuilt binaries ...)
--   other fields: build (rockspec build type), external = { names of system libraries the rock needs }, prebuilt = true when it names .so/.dll/.o files.
-- rs is an evaluated rockspec; tree (optional) is the list of file paths of the unpacked source, used for build types that hide their sources (make, cmake, command).
-- Shortcut: the language of a Makefile/CMake rock is read from file extensions in the tree (vendored third-party code counts too), so it can say "other" for a rock that only builds C.

local M = {}

local LANG = {
  c = "c", h = "c",
  cc = "c++", cpp = "c++", cxx = "c++", hpp = "c++", hh = "c++", hxx = "c++", C = "c++",
  m = "objc", mm = "objc++",
  rs = "rust", go = "go", zig = "zig", nim = "nim", d = "d",
  f = "fortran", f90 = "fortran", f95 = "fortran", for_ = "fortran",
  s = "asm", S = "asm", asm = "asm",
}
local PREBUILT = { so = true, dll = true, dylib = true, o = true, a = true, obj = true, lib = true }

-- build types of the common rockspec build backends and the language they imply
local BUILD_LANG = { ["rust-mlua"] = "rust", cargo = "rust", ["rust"] = "rust", go = "go", zig = "zig" }

local function ext(path) return path:match("%.([%w_]+)$") end

local function note(set, langs, path)
  local e = ext(path)
  if not e or e == "lua" then return end
  if PREBUILT[e] then set.prebuilt = true; return end
  local l = LANG[e]
  if l then langs[l] = true else langs["unknown:" .. e] = true end
end

-- a build.modules value: "file.c" | { "a.c", "b.c", sources = ..., libraries = ..., defines = ..., incdirs = ..., libdirs = ... }
-- Only the array part and `sources` are source files; the other lists name libraries, macros and directories.
local function scan_module(v, set, langs)
  local function src(x)
    if type(x) ~= "string" then return end
    note(set, langs, x)
    if ext(x) ~= "lua" then set.native = true end
  end
  if type(v) == "string" then return src(v) end
  if type(v) ~= "table" then return end
  for _, x in ipairs(v) do src(x) end
  if type(v.sources) == "string" then src(v.sources)
  elseif type(v.sources) == "table" then for _, x in ipairs(v.sources) do src(x) end end
  if v.libraries or v.defines or v.incdirs or v.libdirs then set.native = true end
end

local function scan_build(b, set, langs)
  if type(b) ~= "table" then return end
  for _, v in pairs(b.modules or {}) do scan_module(v, set, langs) end
  if b.libraries or b.defines or b.incdirs or b.libdirs then set.native = true end
  if type(b.install) == "table" and type(b.install.lib) == "table" and next(b.install.lib) then
    set.native = true
    for _, p in pairs(b.install.lib) do if type(p) == "string" then note(set, langs, p) end end
  end
end

function M.classify(rs, tree)
  local set, langs = {}, {}
  local build = type(rs.build) == "table" and rs.build or {}
  local btype = build.type or "builtin"
  if btype == "module" then btype = "builtin" end

  scan_build(build, set, langs)
  for _, p in pairs(build.platforms or {}) do scan_build(p, set, langs) end

  local opaque = false   -- the rockspec does not say what is compiled
  if btype ~= "builtin" and btype ~= "none" then
    set.native = true
    if BUILD_LANG[btype] then langs[BUILD_LANG[btype]] = true else opaque = true end
  end

  local external = {}
  for name in pairs(rs.external_dependencies or {}) do external[#external + 1] = tostring(name) end
  table.sort(external)
  if #external > 0 then set.native = true end

  if not set.native then return { native = false } end

  if opaque and tree then
    for _, p in ipairs(tree) do
      local e = ext(p)
      if e and e ~= "lua" then
        note(set, langs, p)
      end
    end
    -- build-system files are not sources
    langs["unknown:txt"], langs["unknown:cmake"], langs["unknown:md"], langs["unknown:in"] = nil, nil, nil, nil
    for k in pairs(langs) do if k:sub(1, 8) == "unknown:" then langs[k] = nil end end
    opaque = next(langs) == nil
    if opaque and not set.prebuilt and #external == 0 and not (build.libraries or build.defines or build.incdirs or build.libdirs) then
      return { native = "build", build = btype, build_deps = rs.build_dependencies }     -- a build step (make, command, a plugin backend) but no compiled source anywhere in the tree
    end
  end

  local list = {}
  for l in pairs(langs) do list[#list + 1] = l end
  table.sort(list)
  local only_c = not opaque and #list > 0 and #list == 1 and list[1] == "c"
  local bdeps
  for _, d in ipairs(type(rs.build_dependencies) == "table" and rs.build_dependencies or {}) do
    if type(d) == "string" then bdeps = bdeps or {}; bdeps[#bdeps + 1] = d end
  end
  return {
    build_deps = bdeps,   -- rocks that must be installed to build this one (a build backend such as luarocks-build-luke)
    native = only_c and "c" or "other",
    langs = list, build = btype, external = #external > 0 and external or nil,
    prebuilt = set.prebuilt or nil,
    unknown_language = (opaque or #list == 0) or nil,   -- nothing says what is compiled (make/cmake/command without a tree, or only libraries/external deps)
  }
end

return M
