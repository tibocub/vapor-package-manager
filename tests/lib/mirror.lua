-- Builds a file:// mirror on disk for tests.
--   local publish = require("mirror").new(dir)
--   publish{ name = { kind = "lib"|"app", versions = { ["1.0-1"] = { files = {dest = content}, deps = {}, bin = {}, badhash = true } } } }
local fs, hash, json = require("vpm.fs"), require("vpm.hash"), require("json")
local M = {}

function M.new(mirror)
  return function(packages)
    for name, p in pairs(packages) do
      local doc = { name = name, kind = p.kind or "lib", versions = {} }
      for v, m in pairs(p.versions) do
        local files, size = {}, 0
        for dest, content in pairs(m.files) do
          local path = mirror .. "/src/" .. name .. "-" .. v .. "/" .. dest
          assert(fs.mkdirp(path:match("^(.*)/[^/]*$"))); assert(fs.write(path, content))
          files[dest] = { sha256 = m.badhash and string.rep("0", 64) or hash.hex(content), size = #content, url = "file://" .. path }
          size = size + #content
        end
        doc.versions[v] = { deps = m.deps or {}, files = files, bin = m.bin or {}, size = size, summary = m.summary, native = m.native, host = m.host, works = m.works }
      end
      local shard = name:sub(1, 2):lower()
      assert(fs.mkdirp(mirror .. "/index/v1/p/" .. shard))
      assert(fs.write(mirror .. "/index/v1/p/" .. shard .. "/" .. name .. ".json", json.encode(doc)))
    end
    local lines = {}
    for name, p in pairs(packages) do
      local newest
      for v in pairs(p.versions) do newest = v end
      local m = p.versions[newest]
      lines[#lines + 1] = json.compact({ n = name, v = newest, s = m.summary, c = m.native and m.native.native or "pure", h = m.host, w = m.works })
    end
    table.sort(lines)
    assert(fs.write(mirror .. "/index/v1/search.jsonl", table.concat(lines, "\n") .. "\n"))
    assert(fs.write(mirror .. "/index/v1/meta.json", json.encode({ format = 1, lua = "5.4", provided = { lpeg = "1.1.0" } })))
  end
end

return M
