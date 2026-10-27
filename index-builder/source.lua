-- Fetch a rock's source tree onto the local disk, safely (the URLs and archives are untrusted).
-- fetch(rs, dir) -> srcdir, origin     or     nil, reason
-- origin = { type = "git"|"archive", url =, commit = (git), sha256 = (archive), raw = <function path -> url|nil> }
local M = {}

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function run(cmd)
  local p = io.popen(cmd .. " 2>/dev/null; echo \"::rc=$?\"")
  local out = p:read("a"); p:close()
  local rc = tonumber(out:match("::rc=(%d+)%s*$"))
  return rc == 0, (out:gsub("::rc=%d+%s*$", ""))
end

local function git_url(u)
  u = u:gsub("^git%+", ""):gsub("^git://", "https://")
  if u:match("^git@") or u:match("^ssh://") then return nil end
  if not u:match("^https?://") then return nil end
  return u
end

local ARCHIVE = { "%.tar%.gz$", "%.tgz$", "%.zip$", "%.tar%.bz2$", "%.tar%.xz$" }
local function is_archive(u)
  for _, p in ipairs(ARCHIVE) do if u:match(p) then return true end end
end

-- A function mapping a path inside the source dir to a stable raw URL, when the host offers one.
local function raw_for_git(url, commit, prefix)
  local o, r = url:match("^https://github%.com/([^/]+)/([^/]+)")
  if o then
    r = r:gsub("%.git$", "")
    return function(path) return ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(o, r, commit, prefix .. path) end
  end
  o, r = url:match("^https://gitlab%.com/([^/]+)/([^/]+)")
  if o then
    r = r:gsub("%.git$", "")
    return function(path) return ("https://gitlab.com/%s/%s/-/raw/%s/%s"):format(o, r, commit, prefix .. path) end
  end
end

-- github.com/o/r/archive/<ref>.tar.gz|zip  (also .../archive/refs/tags/<ref>)
local function raw_for_archive(url, prefix)
  local o, r, ref = url:match("^https://github%.com/([^/]+)/([^/]+)/archive/(.+)%.tar%.gz$")
  if not o then o, r, ref = url:match("^https://github%.com/([^/]+)/([^/]+)/archive/(.+)%.zip$") end
  if not o then return nil end
  ref = ref:gsub("^refs/tags/", ""):gsub("^refs/heads/", "")
  return function(path) return ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(o, r, ref, prefix .. path) end
end

local function only_dir(dir)
  local ok, out = run("ls -A " .. q(dir))
  if not ok then return nil end
  local names = {}
  for n in out:gmatch("[^\n]+") do names[#names + 1] = n end
  if #names == 1 then
    local isdir = run("test -d " .. q(dir .. "/" .. names[1]))
    if isdir then return names[1] end
  end
end

function M.fetch(rs, dir)
  local src = rs.source
  local url = src.url
  run("mkdir -p " .. q(dir))
  if is_archive(url) then
    if not url:match("^https?://") then return nil, "source-scheme" end
    local file = dir .. "/archive.bin"
    local ok = run(("curl -sSfL -m 120 --max-filesize 30000000 -o %s %s"):format(q(file), q(url)))
    if not ok then return nil, "source-download" end
    local okh, h = run("sha256sum " .. q(file))
    local ex = dir .. "/x"
    run("mkdir -p " .. q(ex))
    local cmd = url:match("%.zip$") and ("unzip -q -o %s -d %s"):format(q(file), q(ex))
                or ("tar -xf %s -C %s --no-same-owner --no-same-permissions"):format(q(file), q(ex))
    if not run(cmd) then return nil, "source-extract" end
    run("rm -f " .. q(file))
    -- source.dir names the directory the archive unpacks into (not a subdirectory of it)
    local top = (src.dir and run("test -d " .. q(ex .. "/" .. src.dir)) and src.dir) or only_dir(ex)
    local root = top and (ex .. "/" .. top) or ex
    local rawf = raw_for_archive(url, "")
    return root, { type = "archive", url = url, sha256 = okh and h:match("^(%x+)") or nil, raw = rawf }
  end

  local gurl = git_url(url)
  if not gurl then return nil, "source-scheme" end
  local work = dir .. "/repo"
  local ref = src.tag or src.branch
  local cmd = "GIT_TERMINAL_PROMPT=0 timeout 120 git -c protocol.allow=never -c protocol.https.allow=always"
              .. " clone -q --depth 1 --no-tags" .. (ref and (" --branch " .. q(ref)) or "") .. " " .. q(gurl) .. " " .. q(work)
  if not run(cmd) then return nil, ref and "source-ref-missing" or "source-download" end
  local okc, commit = run("git -C " .. q(work) .. " rev-parse HEAD")
  if not okc then return nil, "source-download" end
  commit = commit:match("^(%x+)")
  run("rm -rf " .. q(work .. "/.git"))
  -- for git, source.dir only names the clone directory: the tree root is the repository root
  return work, { type = "git", url = gurl, commit = commit, ref = ref, raw = raw_for_git(gurl, commit, "") }
end

M.q, M.run = q, run
return M
