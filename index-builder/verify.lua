-- lua index-builder/verify.lua INDEX_DIR [per_host=3] [github_sample=60]
-- Download sample files from the URLs in the index and compare their sha256 with the recorded one. Checks that the
-- URL rules in source.lua really point at the bytes that were hashed.
package.path = "index-builder/?.lua;" .. package.path
local source = require("source")
local q, run = source.q, source.run
local dir, per_host, gh_n = arg[1], tonumber(arg[2] or 3), tonumber(arg[3] or 60)
math.randomseed(42)

local by_host = {}
local ok, out = run("find " .. q(dir .. "/v1/p") .. " -name '*.json'")
for f in out:gmatch("[^\n]+") do
  local t = io.open(f):read("a")
  for sha, url in t:gmatch('"sha256": "(%x+)",%s*"size": %d+,%s*"url": "([^"]+)"') do
    local host = url:match("^https://([^/]+)/")
    if host then
      by_host[host] = by_host[host] or {}
      table.insert(by_host[host], { url = url, sha = sha })
    end
  end
end

local bad, total = 0, 0
local hosts = {}
for h in pairs(by_host) do hosts[#hosts + 1] = h end
table.sort(hosts)
for _, h in ipairs(hosts) do
  local list = by_host[h]
  local n = (h == "raw.githubusercontent.com") and gh_n or per_host
  local seen = 0
  while seen < math.min(n, #list) do
    local e = table.remove(list, math.random(#list))
    seen = seen + 1; total = total + 1
    local good, got = run(("curl -sSfL -m 30 %s | sha256sum"):format(q(e.url)))
    local sha = got and got:match("^(%x+)")
    if sha ~= e.sha then
      bad = bad + 1
      print(("MISMATCH %s\n   want %s\n   got  %s"):format(e.url, e.sha, tostring(sha)))
    end
  end
  print(("%-32s checked %d of %d"):format(h, seen, seen + #list))
end
print(("verified %d files, %d mismatches"):format(total, bad))
os.exit(bad == 0 and 0 or 1)
