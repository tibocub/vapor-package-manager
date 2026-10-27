-- Runs ON the board (needs cjson and the deployed vpm modules): builds a small file:// mirror at /flash/mirror
-- for trying vpm without a network: seven libraries a..g in a diamond (g needs e,f; e needs d; d needs b,c; b,c need a).
local cjson = require("cjson")
local fs, hash = require("vpm.fs"), require("vpm.hash")
local root = "/flash/mirror"
fs.rmtree(root)
local pk = {
  a = { {}, { ["a.lua"] = string.rep("-- a\n", 200) .. "return 'a'" } },
  b = { { "a" }, { ["b.lua"] = string.rep("-- b\n", 300) .. "return 'b'" } },
  c = { { "a" }, { ["c/init.lua"] = string.rep("-- c\n", 250) .. "return 'c'", ["c/x.lua"] = string.rep("-- x\n", 100) } },
  d = { { "b", "c" }, { ["d.lua"] = string.rep("-- d\n", 400) } },
  e = { { "d" }, { ["e.lua"] = string.rep("-- e\n", 150), ["e/y.lua"] = string.rep("-- y\n", 120) } },
  f = { {}, { ["f.lua"] = string.rep("-- f\n", 500) } },
  g = { { "e", "f" }, { ["g.lua"] = string.rep("-- g\n", 200) } },
}
for name, p in pairs(pk) do
  local doc = { name = name, kind = "lib", versions = { ["1.0-1"] = { deps = p[1], files = {}, bin = {}, size = 0 } } }
  for dest, content in pairs(p[2]) do
    local path = root .. "/src/" .. name .. "/" .. dest
    assert(fs.mkdirp(path:match("^(.*)/[^/]*$"))); assert(fs.write(path, content))
    doc.versions["1.0-1"].files[dest] = { sha256 = hash.hex(content), size = #content, url = "file://" .. path }
    doc.versions["1.0-1"].size = doc.versions["1.0-1"].size + #content
  end
  assert(fs.mkdirp(root .. "/index/v1/p/" .. name))
  assert(fs.write(root .. "/index/v1/p/" .. name .. "/" .. name .. ".json", cjson.encode(doc)))
end
assert(fs.write(root .. "/index/v1/meta.json", cjson.encode({ format = 1, provided = {} })))
print("MIRROR ready at " .. root)
