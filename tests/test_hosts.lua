package.path = "lib/?.lua;tests/lib/?.lua;" .. package.path
local index = require("vpm.index")
local files = {
  ["meta.json"] = '{"serial":1,"provided":{}}',
  ["p/pl/plain.json"] = '{"name":"plain","kind":"lib","versions":{"1.0-1":{"deps":[]}}}',
  ["p/ff/ffi-thing.json"] = '{"name":"ffi-thing","kind":"lib","versions":{"1.0-1":{"deps":[],"host":"luajit"}}}',
  ["p/mi/mixed.json"] = '{"name":"mixed","kind":"lib","versions":{"1.0-1":{"deps":[],"host":"nvim"},"0.9-1":{"deps":[]}}}',
}
local function new(hosts)
  return index.new{ base = "mem://", decode = require("json_decode"), hosts = hosts,
    transport = { fetch = function(url) local f = files[url:gsub("^mem://", "")]; if f then return f end return nil, 404, "nf" end } }
end

local ix = new()
assert(ix:resolver_view("plain"), "an ordinary package is offered")
assert(ix:resolver_view("ffi-thing"), "host-specific packages are visible by default")
assert(ix:resolver_view("mixed").versions["1.0-1"] and ix.hidden == nil, "all versions, nothing hidden")

ix = new({})   -- an explicit (empty) list of hosts filters
assert(ix:resolver_view("ffi-thing") == nil and ix.hidden["ffi-thing"] == "luajit", "filtered: hidden and says why")
local v = ix:resolver_view("mixed")
assert(v and v.versions["0.9-1"] and not v.versions["1.0-1"], "only the versions that fit are offered")
assert(ix:resolver_view("nope") == nil and ix.hidden["nope"] == nil, "unknown is not 'hidden'")

ix = new({ "luajit", "nvim" })
assert(ix:resolver_view("ffi-thing"), "allowed by the config")
assert(ix:resolver_view("mixed").versions["1.0-1"], "and the nvim version too")
print("hosts ok")
