-- Index signing (docs/signing.md). Uses openssl's ed25519; the device only verifies (vaporOS vlua/vsign.c).
--   lua index-builder/sign.lua keygen KEY.pem          create a private key, print the public key (64 hex chars)
--   lua index-builder/sign.lua pubkey KEY.pem          print the public key again
--   lua index-builder/sign.lua sign KEY.pem INDEX_V1   write FILE.sig (64 raw bytes) next to meta.json and p/*/*.json
-- A signature covers the exact bytes of its file. meta.json carries the build `serial` (see emit).
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function sh(cmd)
  local p = assert(io.popen(cmd, "r")); local out = p:read("a"); local ok = p:close()
  assert(ok, "failed: " .. cmd)
  return out
end

local function pubkey(key)
  -- the DER SubjectPublicKeyInfo of an ed25519 key ends with the 32 raw key bytes
  local der = sh(("openssl pkey -in %s -pubout -outform DER"):format(q(key)))
  return (der:sub(-32):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local cmd = arg[1]
if cmd == "keygen" then
  sh(("umask 077; openssl genpkey -algorithm ed25519 -out %s"):format(q(arg[2])))
  print(pubkey(arg[2]))
elseif cmd == "pubkey" then
  print(pubkey(arg[2]))
elseif cmd == "sign" then
  local key, dir = arg[2], arg[3]
  local list = sh(("cd %s && ls meta.json p/*/*.json"):format(q(dir)))
  local n = 0
  for f in list:gmatch("[^\n]+") do
    sh(("openssl pkeyutl -sign -rawin -inkey %s -in %s -out %s"):format(q(key), q(dir .. "/" .. f), q(dir .. "/" .. f .. ".sig")))
    n = n + 1
  end
  print(("signed %d files with key %s"):format(n, pubkey(key)))
else
  io.stderr:write("usage: sign.lua keygen KEY | pubkey KEY | sign KEY INDEX_V1_DIR\n"); os.exit(2)
end
