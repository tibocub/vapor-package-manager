-- Filesystem layer. lfs (always present in vlua, also on the sim and boards) does the directory work; without it
-- (a plain host Lua running the tests) a shell fallback is used. shortcut: the shell fallback is for tests only
-- and quotes with single quotes, so it must never see untrusted names; use lfs for anything real.
local M = {}
local ok, lfs = pcall(require, "lfs")

local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

if ok then
  function M.isdir(p) return lfs.attributes(p, "mode") == "directory" end
  function M.list(p)
    local t = {}
    for n in lfs.dir(p) do if n ~= "." and n ~= ".." then t[#t + 1] = n end end
    table.sort(t)
    return t
  end
  function M.mkdir(p) return lfs.mkdir(p) end
  function M.rmdir(p) return lfs.rmdir(p) end
else
  local function sh(c) return os.execute(c .. " >/dev/null 2>&1") end
  function M.isdir(p) return sh("test -d " .. q(p)) == true end
  function M.list(p)
    local h = assert(io.popen("ls -A " .. q(p) .. " 2>/dev/null"))
    local t = {}
    for n in h:lines() do t[#t + 1] = n end
    h:close(); table.sort(t)
    return t
  end
  function M.mkdir(p) return sh("mkdir " .. q(p)) end
  function M.rmdir(p) return sh("rmdir " .. q(p)) end
end

function M.exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end return M.isdir(p) end
function M.isfile(p) return M.exists(p) and not M.isdir(p) end

-- Recursive: one existence check when the directory is already there (on littlefs each check costs ~35 ms).
function M.mkdirp(p)
  if p == "" or p == "/" or M.isdir(p) then return true end
  local ok, err = M.mkdirp(p:match("^(.*)/[^/]*$") or "")
  if not ok then return nil, err end
  if not M.mkdir(p) and not M.isdir(p) then return nil, "cannot create " .. p end
  return true
end

function M.read(p) local f, e = io.open(p, "rb"); if not f then return nil, e end local s = f:read("a"); f:close(); return s end
function M.write(p, s)
  local f, e = io.open(p, "wb"); if not f then return nil, e end
  f:write(s); f:close(); return true
end
function M.size(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local n = f:seek("end"); f:close(); return n
end

function M.remove(p) return os.remove(p) end
function M.rename(a, b) return os.rename(a, b) end

function M.rmtree(p)
  if M.isdir(p) then
    for _, n in ipairs(M.list(p)) do M.rmtree(p .. "/" .. n) end
    M.rmdir(p)
  elseif M.exists(p) then
    os.remove(p)
  end
end

-- remove empty directories upward from `dir`, stopping at (and keeping) `stop`
function M.prune(dir, stop)
  while dir ~= stop and #dir > #stop and M.isdir(dir) and #M.list(dir) == 0 do
    M.rmdir(dir)
    dir = dir:match("^(.*)/[^/]*$") or stop
  end
end

return M
