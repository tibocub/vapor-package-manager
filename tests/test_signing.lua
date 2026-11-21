package.path = "lib/?.lua;tests/lib/?.lua;" .. package.path
local index = require("vpm.index")

-- fake "crypto": the signature of msg under key is a 64-byte string derived from both
local function fakesig(key, msg)
  local h = 0
  for i = 1, #msg do h = (h * 31 + msg:byte(i)) % 4294967291 end
  return ((("%s|%d|%d"):format(key, #msg, h)) .. ("_"):rep(64)):sub(1, 64)
end
local function verify(sig, msg, key) return sig == fakesig(key, msg) end

local KEY, KEY2, OTHER = ("k"):rep(32), ("j"):rep(32), ("x"):rep(32)
local meta = '{"serial":100,"provided":{"lpeg":"1.1.0"}}'
local pkg = '{"name":"foo","kind":"lib","versions":{"1.0-1":{"deps":[]}}}'

local function server(files)
  return { fetch = function(url)
    local path = url:gsub("^mem://", "")
    if files[path] then return files[path] end
    return nil, 404, "not found"
  end }
end
local function signed(key, bad)
  local f = { ["meta.json"] = meta, ["meta.json.sig"] = fakesig(key, meta),
              ["p/fo/foo.json"] = pkg, ["p/fo/foo.json.sig"] = fakesig(key, pkg) }
  if bad then f["p/fo/foo.json"] = pkg:gsub("lib", "app") end      -- changed after signing
  return f
end
local function new(files, keys, serial_file)
  return index.new{ base = "mem://", transport = server(files), decode = require("json_decode"),
                    keys = keys, verify = verify, serial_file = serial_file }
end

-- valid signature
local ix = new(signed(KEY), { KEY })
local d0, e0 = ix:package("foo"); assert(d0, e0); assert(d0.kind == "lib")
assert(ix:meta().provided.lpeg == "1.1.0")

-- second trusted key
assert(new(signed(KEY2), { KEY, KEY2 }):package("foo"))

-- not signed by a trusted key
local doc, err = new(signed(OTHER), { KEY }):package("foo")
assert(not doc and err:match("bad signature"), err)

-- package changed after signing
doc, err = new(signed(KEY, true), { KEY }):package("foo")
assert(not doc and err:match("bad signature"), err)

-- a failed signature is remembered so commands can report it (exit 4) instead of "not in the index"; a plain miss is not a failure
local badix = new(signed(KEY, true), { KEY })
assert(badix:resolver_view("foo") == nil and badix.failed and badix.failed:match("bad signature"), tostring(badix.failed))
local okix = new(signed(KEY), { KEY })
assert(okix:resolver_view("nope") == nil and okix.failed == nil, "a missing package is not an integrity failure")

-- missing signature
local f = signed(KEY); f["p/fo/foo.json.sig"] = nil
doc, err = new(f, { KEY }):package("foo")
assert(not doc and err:match("no valid signature"), err)

-- a bad meta blocks packages too
f = signed(KEY); f["meta.json.sig"] = fakesig(OTHER, meta)
doc, err = new(f, { KEY }):package("foo")
assert(not doc and err:match("bad signature"), err)

-- no keys configured: nothing is checked, no .sig needed
f = signed(KEY); f["p/fo/foo.json.sig"] = nil; f["meta.json.sig"] = nil
assert(new(f, nil):package("foo"))

-- rollback: the serial seen once is a floor
local sf = os.tmpname()
os.remove(sf)
local dir = sf .. "-d"; os.execute("mkdir -p " .. dir)
sf = dir .. "/.vpm/index-serial"
assert(new(signed(KEY), { KEY }, sf):meta())
assert(io.open(sf):read("a") == "100")
meta = '{"serial":99}'
doc, _, err = new(signed(KEY), { KEY }, sf):meta()
assert(not doc and err:match("older than one already seen"), err)
meta = '{"serial":101}'
assert(new(signed(KEY), { KEY }, sf):meta())
assert(io.open(sf):read("a") == "101")
meta = '{"nothing":1}'
doc, _, err = new(signed(KEY), { KEY }, sf):meta()
assert(not doc and err:match("no serial"), err)
os.execute("rm -rf " .. dir)

print("signing ok")
