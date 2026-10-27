-- lua tools/build-dist.lua OUTDIR CONFIG [--source]
-- Builds the tree to copy onto a device (relative to the root of its filesystem): lib/lua/vpm/**.lua as stripped
-- bytecode (loaded by `require` from files named .lua; about 40% less heap than source, R4), the launcher
-- under <bindir>/vpm and the board config as etc/vpm.lua. Bytecode is built on the PC and is tied to the Lua
-- build: both must be 5.4 with 64-bit integers (checked at load time by the interpreter).
local out, cfgpath, source = arg[1], arg[2], arg[3] == "--source"
assert(out and cfgpath, "usage: lua tools/build-dist.lua OUTDIR CONFIG [--source]")

local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function write(p, s)
  os.execute("mkdir -p " .. q(p:match("^(.*)/[^/]*$")))
  local f = assert(io.open(p, "wb")); f:write(s); f:close()
end

local cfg = assert(load(read(cfgpath), "=" .. cfgpath, "t", {}))()
os.execute("rm -rf " .. q(out))
local n, bytes = 0, 0
for path in io.popen("cd lib && find vpm -name '*.lua' | sort"):lines() do
  local src = read("lib/" .. path)
  local data = source and src or string.dump(assert(load(src, "@" .. path)), true)
  write(out .. "/lib/lua/" .. path, data)
  n, bytes = n + 1, bytes + #data
end
write(out .. "/" .. cfg.bindir:gsub("^/[^/]+/", "") .. "/vpm", read("tools/launcher.lua"))
write(out .. "/etc/vpm.lua", read(cfgpath))
print(("%d modules, %d bytes (%s), launcher at %s/vpm, config etc/vpm.lua"):format(n, bytes, source and "source" or "stripped bytecode", cfg.bindir))
