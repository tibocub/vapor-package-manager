-- Library compatibility test: install a rock with vpm, then load each of its modules under vlr in a sandbox (bubblewrap: no network, read-only system,
-- scratch /tmp only) with memory, CPU and file-size limits, in the 5.1 dialect and the 5.4 dialect.
--   VLR=vlr-path INDEX=http://127.0.0.1:PORT/index/v1 KEYS=hex RECDIR=dir OUT=dir  vlr tools/libtest/driver.lua NAME
-- Writes OUT/results/NAME.tsv: one line per module: NAME <TAB> module <TAB> 5.1 result <TAB> 5.4 result
local name = arg[1]
local VLR, INDEX, KEYS, RECDIR, OUT = os.getenv("VLR"), os.getenv("INDEX"), os.getenv("KEYS"), os.getenv("RECDIR"), os.getenv("OUT")
local here = (arg[0]:match("^(.*)/[^/]*$") or ".")
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sh(cmd) local p = io.popen(cmd .. " 2>&1"); local o = p:read("a"); local ok, _, code = p:close(); return o, code end
local cwd = sh("pwd"):gsub("\n$", "")
if not here:match("^/") then here = cwd .. "/" .. here end
local vpm = here .. "/../.."

local rec = dofile(("%s/%s.lua"):format(RECDIR, name))
local root = ("%s/pkgs/%s"):format(OUT, name)
sh("rm -rf " .. q(root) .. " && mkdir -p " .. q(root .. "/lib") .. " " .. q(root .. "/apps") .. " " .. q(root .. "/bin") .. " " .. q(root .. "/proj"))
local cfg = io.open(root .. "/config.lua", "w")
cfg:write(("return {libdir=%q, appdir=%q, bindir=%q, index=%q, reserve=0, profile='full', keys={%q}}\n"):format(root .. "/lib", root .. "/apps", root .. "/bin", INDEX, KEYS))
cfg:close()

local out = io.open(("%s/results/%s.tsv"):format(OUT, name), "w")
local function line(mod, a, b) out:write(("%s\t%s\t%s\t%s\n"):format(name, mod, a, b)); out:flush() end

-- Installing a C rock compiles third-party source, so it happens in a sandbox too: network (the index and luarocks.org), a read-only system, only /w (this package's scratch folder) writable.
-- Pure rocks only download files and stay outside, as before.
local o, code
if rec.native then
  local cfgw = io.open(root .. "/config.lua", "w")
  cfgw:write(("return {libdir='/w/lib', appdir='/w/apps', bindir='/w/bin', index=%q, reserve=0, profile='full', keys={%q}}\n"):format(INDEX, KEYS))
  cfgw:close()
  local cmd = "cd /w/proj && ulimit -v 4194304 -t 150 -f 200000 2>/dev/null; exec timeout 170 /vlr /vpm/bin/vpm.lua --config=/w/config.lua --allow-scripts -y -g install " .. q(name)
  local full = ("bwrap --unshare-all --share-net --die-with-parent --new-session --clearenv --setenv HOME /tmp --setenv PATH /usr/bin:/bin --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 "
    .. "--symlink usr/bin /bin --symlink usr/sbin /sbin --ro-bind /etc/pki /etc/pki --ro-bind-try /etc/alternatives /etc/alternatives --ro-bind-try /etc/os-release /etc/os-release --ro-bind /etc/resolv.conf /etc/resolv.conf --ro-bind /etc/hosts /etc/hosts --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf "
    .. "--ro-bind %s /vlr --ro-bind %s /vpm --bind %s /w --tmpfs /tmp --proc /proc --dev /dev --chdir /w/proj sh -c %s"):format(q(VLR), q(vpm), q(root), q(cmd))
  o, code = sh(full)
else
  o, code = sh(("cd %s && timeout 120 %s %s --config=%s -y -g install %s"):format(q(root .. "/proj"), q(VLR), q(vpm), q(root .. "/config.lua"), q(name)))
end
do local lf = io.open(root .. "/install.log", "w"); if lf then lf:write(o); lf:close() end end
if code ~= 0 then line("-", "INSTALL-FAILED", (o:gsub("\n.*$", ""):sub(1, 200))); out:close(); return end

local function try(mod, dialect)
  -- /vlr is the runtime, /libs the installed libraries (read-only), /tmp a fresh tmpfs; nothing else is writable and there is no network
  local cmd = ("ulimit -v 1048576 -t 20 -f 2000 2>/dev/null; exec timeout 25 /vlr %s /check.lua /libs/lib /libs/apps/%s %s"):format(dialect, name, q(mod))
  local full = ("bwrap --unshare-all --die-with-parent --new-session --clearenv --setenv HOME /tmp --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 "
    .. "--symlink usr/bin /bin --ro-bind /etc/pki /etc/pki --ro-bind %s /vlr --ro-bind %s /check.lua --ro-bind %s /libs --tmpfs /tmp --proc /proc --dev /dev --chdir /tmp sh -c %s"):format(
    q(VLR), q(here .. "/check.lua"), q(root), q(cmd))
  local r = sh(full)
  r = r:gsub("%s+$", "")
  if r == "" then return "NO-OUTPUT" end
  return (r:gsub("\n", " | "):sub(1, 220))
end

-- a make or cmake rock does not say which modules it installs: take them from the installed files
local modules = rec.modules or {}
if #modules == 0 then
  local p = io.popen(("cd %s && find . -type f \\( -name '*.lua' -o -name '*.so' \\) -not -path './.vpm*' 2>/dev/null"):format(q(root .. "/lib")))
  for f in p:lines() do
    local m = f:gsub("^%./", ""):gsub("%.[^./]*$", ""):gsub("/init$", ""):gsub("/", ".")
    modules[#modules + 1] = m
  end
  p:close()
  table.sort(modules)
end
for _, mod in ipairs(modules) do line(mod, try(mod, ""), try(mod, "--dialect=5.4")) end
if #modules == 0 then line("-", "NO-MODULES", "") end
out:close()
