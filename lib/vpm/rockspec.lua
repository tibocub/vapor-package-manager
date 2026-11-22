-- A rockspec (the file luarocks.org takes) from a vpm.lua manifest, its file list and the git source. Pure: no I/O, so it is easy to test.
-- Only what a pure-Lua project needs: builtin build, one module per .lua file, bin scripts for programs.
local M = {}

local function q(s) return (("%q"):format(s):gsub("\\\n", "\\n")) end

-- "x/y.lua" -> "x.y", "x/init.lua" -> "x"
function M.module_name(path)
  local n = path:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
  return n
end

-- m: the manifest table (name, version, kind, bin, deps, description, license, homepage); files: sorted relative paths;
-- src: { url = "git+https://...", tag = "v1.0" }; revision: rockspec revision (default 1)
function M.generate(m, files, src, revision)
  local ver = m.version:match("%-%d+$") and m.version or (m.version .. "-" .. (revision or 1))
  local out = { 'rockspec_format = "3.0"', "package = " .. q(m.name), "version = " .. q(ver),
    ("source = { url = %s, tag = %s }"):format(q(src.url), q(src.tag)) }
  local d = { "summary = " .. q(m.description or m.name) }
  if m.homepage then d[#d + 1] = "homepage = " .. q(m.homepage) end
  if m.license then d[#d + 1] = "license = " .. q(m.license) end
  out[#out + 1] = "description = { " .. table.concat(d, ", ") .. " }"
  local deps = { q("lua >= 5.1") }
  local names = {}
  for n in pairs(m.deps or {}) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do deps[#deps + 1] = q((n .. " " .. m.deps[n]):gsub("%s+$", "")) end
  out[#out + 1] = "dependencies = { " .. table.concat(deps, ", ") .. " }"
  local isbin = {}
  for _, f in pairs(m.bin or {}) do isbin[f] = true end
  local mods = {}
  for _, f in ipairs(files) do if not isbin[f] then mods[#mods + 1] = ("    [%s] = %s,"):format(q(M.module_name(f)), q(f)) end end
  out[#out + 1] = "build = {\n  type = \"builtin\",\n  modules = {\n" .. table.concat(mods, "\n") .. (#mods > 0 and "\n" or "") .. "  },"
  local bins, cmds = {}, {}
  for c in pairs(m.bin or {}) do cmds[#cmds + 1] = c end
  table.sort(cmds)
  for _, c in ipairs(cmds) do bins[#bins + 1] = ("%s = %s"):format("[" .. q(c) .. "]", q(m.bin[c])) end
  if #bins > 0 then out[#out] = out[#out] .. "\n  install = { bin = { " .. table.concat(bins, ", ") .. " } }," end
  out[#out] = out[#out] .. "\n}"
  return table.concat(out, "\n") .. "\n", ver
end

-- a git remote as the URL a rockspec wants: git+https://host/path.git
function M.source_url(remote)
  remote = (remote or ""):gsub("%s+$", "")
  local host, path = remote:match("^git@([^:]+):(.+)$")
  if not host then host, path = remote:match("^ssh://git@([^/]+)/(.+)$") end
  if host then return "git+https://" .. host .. "/" .. path end
  if remote:match("^git%+https://") then return remote end
  if remote:match("^https://") then return "git+" .. remote end
  return nil, "cannot turn the git remote '" .. remote .. "' into a public https source URL (use --source=URL)"
end

return M
