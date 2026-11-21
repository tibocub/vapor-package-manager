-- Transports: get(url, sink) streams the body to sink(chunk) and returns an HTTP-like status (200, 404...).
-- file:// is the offline path (an SD card, a mirror directory, tests). http(s):// goes through vlr's std.http (needs the vapor.net/vapor.tls/std.http modules).
local fs = require("vpm.fs")
local M = {}

local CHUNK = 2048

function M.get(url, sink)
  local path = url:match("^file://(.*)$")
  if path then
    local f = io.open(path, "rb")
    if not f then return 404, "not found: " .. path end
    while true do
      local chunk = f:read(CHUNK)
      if not chunk then break end
      sink(chunk)
    end
    f:close()
    return 200
  end
  if url:match("^https?://") then -- vlr's own client: redirects, chunked bodies, TLS with the chain and host name always verified
    local ok, std = pcall(require, "std.http")
    if not ok then return 502, "this runtime has no std.http" end
    local r, err = std.get(url, {sink = sink, cafile = M.cafile})
    if not r then return 502, err end
    if r.status ~= 200 then return r.status, r.reason end
    return 200
  end
  return 400, "unsupported URL: " .. url
end

-- whole body as a string (small metadata only); nil, status, err when not 200
function M.fetch(url)
  local parts = {}
  local status, err = M.get(url, function(c) parts[#parts + 1] = c end)
  if status ~= 200 then return nil, status, err end
  return table.concat(parts)
end

return M
