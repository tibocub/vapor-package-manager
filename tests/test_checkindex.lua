package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
-- tools/check-index.lua: a good signed index passes; a dangling blob, a tampered file and a missing catalogue signature are each reported
if os.execute("command -v openssl >/dev/null 2>&1") ~= 0 then print("check-index skipped (no openssl)"); return end
local vlr = os.getenv("VLR") or "vlr"
local hash = require("vpm.hash")
local base = os.tmpname(); os.remove(base)
local function sh(cmd) local ok = os.execute(cmd .. " >/dev/null 2>&1"); return ok == 0 or ok == true end
local function write(p, d) local f = assert(io.open(p, "wb")); f:write(d); f:close() end
assert(sh(("mkdir -p %s/idx/index/v1/p/ex %s/idx/blobs"):format(base, base)))
local data = "return 'hello'\n"
local h = hash.hex(data)
assert(sh(("mkdir -p %s/idx/blobs/%s"):format(base, h:sub(1, 2))))
write(("%s/idx/blobs/%s/%s"):format(base, h:sub(1, 2), h), data)
write(base .. "/idx/index/v1/meta.json", '{"serial":1,"format":1}\n')
write(base .. "/idx/index/v1/p/ex/example.json", ('{"name":"example","kind":"lib","versions":{"1.0-1":{"files":{"example.lua":{"sha256":"%s","size":%d,"url":"blob:%s"}}}}}\n'):format(h, #data, h))
write(base .. "/idx/index/v1/search.jsonl", '{"n":"example","v":"1.0-1"}\n')
local p = io.popen(("%s index-builder/sign.lua keygen %s/key.pem"):format(vlr, base)); local pub = p:read("a"):gsub("%s+", ""); p:close()
local function sign() assert(sh(("%s index-builder/sign.lua sign %s/key.pem %s/idx/index/v1"):format(vlr, base, base))) end
local function check() return sh(("%s tools/check-index.lua %s/idx %s"):format(vlr, base, pub)) end
sign()
assert(check(), "a good signed index passes")
assert(sh(("rm %s/idx/index/v1/search.jsonl.sig"):format(base)) and not check(), "a missing signature is reported")
sign()
assert(check())
write(base .. "/idx/index/v1/p/ex/example.json", ('{"name":"example","kind":"lib","versions":{"1.0-1":{"files":{"example.lua":{"sha256":"%s","size":%d,"url":"blob:%s"}}},"2.0-1":{}}}\n'):format(h, #data, h))
assert(not check(), "a changed file no longer matches its signature")
sign()
assert(check())
assert(sh(("rm %s/idx/blobs/%s/%s"):format(base, h:sub(1, 2), h)) and not check(), "a dangling blob reference is reported")
sh("rm -rf " .. base)
print("check-index ok")
