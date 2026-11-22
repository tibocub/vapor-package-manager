-- Checks the native-code classifier against reality.
--   lua tools/classify-audit.lua stats  MANIFEST RSPEC_DIR                     classify every rockspec, count the classes
--   lua tools/classify-audit.lua pick   MANIFEST RSPEC_DIR N SEED              print N random "name version" lines (seeded)
--   lua tools/classify-audit.lua one    NAME VERSION RSPEC_DIR WORK            fetch the source, print one TSV line: name, from-rockspec, from-rockspec+tree, truth, languages in the tree
-- Truth = what the unpacked tree contains outside tests/docs/examples (source files by extension), compared with what the rockspec says.
package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local manifest, sandbox, source = require("manifest"), require("sandbox"), require("source")
local classify = require("classify").classify

local function class(r) return r.native == false and "pure" or r.native end
local function load_spec(dir, name, ver)
  local f = io.open(("%s/%s-%s.rockspec"):format(dir, name, ver), "rb")
  return f and sandbox.load(f:read("a"), name)
end

local cmd = arg[1]
if cmd == "stats" or cmd == "pick" then
  local repo = manifest.load(arg[2])
  local names = {}
  for n in pairs(repo) do names[#names + 1] = n end
  table.sort(names)
  if cmd == "pick" then
    math.randomseed(tonumber(arg[5]))
    for i = #names, 2, -1 do local j = math.random(i); names[i], names[j] = names[j], names[i] end
    for i = 1, tonumber(arg[4]) do print(names[i], manifest.latest(repo[names[i]])) end
    return
  end
  local count, ext = {}, 0
  for _, n in ipairs(names) do
    local ver = manifest.latest(repo[n])
    local rs = load_spec(arg[3], n, ver)
    if rs then
      local r = classify(rs)
      local k = class(r) .. (r.unknown_language and " (language unknown)" or "")
      count[k] = (count[k] or 0) + 1
      if r.external then ext = ext + 1 end
    else count["rockspec unreadable"] = (count["rockspec unreadable"] or 0) + 1 end
  end
  for k, v in pairs(count) do print(("%6d  %s"):format(v, k)) end
  print(("%6d  with external_dependencies"):format(ext))
  return
end

assert(cmd == "one")
local name, ver, specdir, work = arg[2], arg[3], arg[4], arg[5]
assert(name:match("^[%w][%w%._%-]*$") and ver:match("^[%w][%w%._%-]*$"))
local rs = load_spec(specdir, name, ver)
if not rs then print(name .. "\tunreadable") return end
local a = classify(rs)
local dir = ("%s/%s-%s"):format(work, name, ver)
local root, origin = source.fetch(rs, dir)
if not root then print(name .. "\tfetch-failed\t" .. tostring(origin)) return end
local ok, out = source.run(("cd %s && find . -type f -not -path './.git/*' | head -20000"):format(source.q(root)))
local tree, src = {}, {}
local SKIP = { "^test/", "^tests/", "^spec/", "^doc/", "^docs/", "^example/", "^examples/", "^samples?/", "^bench", "^%.github/" }
for p in out:gmatch("[^\n]+") do
  p = p:gsub("^%./", "")
  tree[#tree + 1] = p
  local skip = false
  for _, pat in ipairs(SKIP) do if p:find(pat) then skip = true end end
  if not skip then src[#src + 1] = p end
end
local b = classify(rs, tree)
-- truth from the tree without tests/docs/examples
local truth = classify({ package = name, version = ver, source = rs.source, build = { type = "make" } }, src)
local tc = (truth.native == "build" or #(truth.langs or {}) == 0) and "pure" or class(truth)
-- build-system-only languages do not count: a tree with cmake/make files and nothing else is pure
local langs = table.concat(truth.langs or {}, ",")
-- for builtin/none the rockspec says exactly what is compiled, so the tree is only a cross-check for build types that hide it
local btype = rs.build and rs.build.type or "builtin"
local opaque = btype ~= "builtin" and btype ~= "none" and btype ~= "module"
print(table.concat({ name, class(a), class(b), opaque and tc or "-", langs, btype, opaque and "" or tc }, "\t"))
source.run("rm -rf " .. source.q(dir))
