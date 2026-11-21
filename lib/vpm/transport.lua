-- Transports: get(url, sink) streams the body to sink(chunk) and returns an HTTP-like status (200, 404...).
-- file:// is the offline path (an SD card, a mirror directory, tests). http:// goes through vpm.http over vsock;
-- https:// answers 502 until a TLS connection exists (docs/vaporos-prerequisites.md P4). M.connect can be replaced (tests).
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
  if url:match("^https?://") then
    if not M.connect and not package.loaded["vsock"] then -- on vlr: the runtime's own client (redirects, chunked, TLS verified)
      local ok, std = pcall(require, "std.http")
      if ok then
        local r, err = std.get(url, {sink = sink, cafile = M.cafile})
        if not r then return 502, err end
        if r.status ~= 200 then return r.status, r.reason end
        return 200
      end
    end
    local http = require("vpm.http")
    http.cafile = M.cafile
    return http.get(url, sink, M.connect or http.vsock_connect)
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
