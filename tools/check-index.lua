-- Pre-publish gate: vlr tools/check-index.lua INDEX_ROOT PUBKEY_HEX
-- INDEX_ROOT holds index/v1 and blobs/. Verifies with vpm's own code: every file has a valid signature, every package file parses, every `blob:` reference exists with the
-- right sha256 and size, search.jsonl lines match the package files. Prints each problem and exits 1 if there is any.
package.path = (arg[0]:match("^(.*)/tools/[^/]*$") or ".") .. "/lib/?.lua;" .. package.path
local root, key = arg[1], arg[2]
if not root or not key then io.stderr:write("usage: vlr tools/check-index.lua INDEX_ROOT PUBKEY_HEX\n"); os.exit(2) end
local verify = require("vapor.sign").verify
key = (key:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
if #key ~= 32 then io.stderr:write("the public key must be 64 hex digits\n"); os.exit(2) end
local hash = require("vpm.hash")
local cj = require("cjson.safe")
local function read(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("a"); f:close(); return d end
local problems = 0
local function bad(fmt, ...) problems = problems + 1; if problems <= 30 then print(("PROBLEM " .. fmt):format(...)) end end

local v1 = root .. "/index/v1"
local function check_signed(rel)
  local body, sig = read(v1 .. "/" .. rel), read(v1 .. "/" .. rel .. ".sig")
  if not body then bad("missing %s", rel); return nil end
  if not sig or #sig ~= 64 then bad("no valid .sig for %s", rel); return body end
  if not verify(sig, body, key) then bad("bad signature on %s", rel) end
  return body
end

local meta = check_signed("meta.json")
local m = meta and cj.decode(meta)
if not m or type(m.serial) ~= "number" then bad("meta.json has no serial") end
local catalogue = check_signed("search.jsonl")

local list = io.popen(("cd %q && ls p/*/*.json"):format(v1))
local names, files, refs = {}, 0, 0
for rel in list:lines() do
  files = files + 1
  local body = check_signed(rel)
  local doc = body and cj.decode(body)
  if not doc or type(doc.versions) ~= "table" then bad("%s does not parse", rel)
  else
    names[doc.name] = true
    for ver, v in pairs(doc.versions) do
      for dest, f in pairs(v.files or {}) do
        local h = type(f.url) == "string" and f.url:match("^blob:(%x+)$")
        if h then
          refs = refs + 1
          local data = read(("%s/blobs/%s/%s"):format(root, h:sub(1, 2), h))
          if not data then bad("%s %s: blob for %s is not stored", doc.name, ver, dest)
          elseif hash.hex(data) ~= h or h ~= f.sha256 or #data ~= f.size then bad("%s %s: blob for %s does not match its hash or size", doc.name, ver, dest) end
        end
      end
    end
  end
end
list:close()
local lines = 0
for l in (catalogue or ""):gmatch("[^\n]+") do
  lines = lines + 1
  local e = cj.decode(l)
  if not e or not names[e.n] then bad("search.jsonl names a package that has no file: %s", l:sub(1, 60)) end
end
if lines ~= files then bad("search.jsonl has %d lines, %d package files", lines, files) end
print(("checked %d package files, %d blob references, %d catalogue lines: %d problem(s)"):format(files, refs, lines, problems))
os.exit(problems == 0 and 0 or 1)
