-- Minimal HTTP/1.1 GET over a connection object { send(data), recv(max, timeout), close() } (vsock's, or a fake in
-- the tests). The body is streamed to sink(chunk), never held whole. Handles Content-Length, chunked and
-- read-until-close bodies and up to 5 redirects. https:// needs `connect_tls` (not built yet: 501).
local M = {}

local MAX_REDIRECTS, TIMEOUT = 5, 20

local function parse_url(url)
  local scheme, host, port, path = url:match("^(https?)://([^/:?#]+):?(%d*)([^#]*)")
  if not scheme then return nil end
  if path == "" or path:sub(1, 1) == "?" then path = "/" .. path end
  return scheme, host, tonumber(port) or (scheme == "https" and 443 or 80), path
end

-- a buffered reader over the connection: line() and body pieces share one buffer
local function reader(conn)
  local buf, eof = "", false
  local r = {}
  local function fill()
    local d, err = conn:recv(2048, TIMEOUT)
    if d == nil then return nil, err end
    if d == "" then eof = true else buf = buf .. d end
    return true
  end
  function r.line()
    while true do
      local i = buf:find("\r\n", 1, true)
      if i then local l = buf:sub(1, i - 1); buf = buf:sub(i + 2); return l end
      if eof then return nil, "connection closed" end
      local ok, err = fill()
      if not ok then return nil, err end
    end
  end
  -- up to n bytes (or whatever is available), nil at end of data
  function r.read(n)
    if buf == "" and not eof then
      local ok, err = fill()
      if not ok then return nil, err end
    end
    if buf == "" then return nil end
    local s = buf:sub(1, n); buf = buf:sub(#s + 1)
    return s
  end
  return r
end

local function body(r, headers, sink)
  local te = (headers["transfer-encoding"] or ""):lower()
  if te:find("chunked", 1, true) then
    while true do
      local l, err = r.line()
      if not l then return nil, err end
      local n = tonumber(l:match("^%x+"), 16)
      if not n then return nil, "bad chunk size" end
      if n == 0 then return true end
      while n > 0 do
        local d, e = r.read(n)
        if not d then return nil, e or "connection closed in a chunk" end
        sink(d); n = n - #d
      end
      r.line()                                 -- the CRLF after the chunk
    end
  end
  local left = tonumber(headers["content-length"])
  while left == nil or left > 0 do
    local d, e = r.read(left or 2048)
    if not d then
      if e then return nil, e end
      return left == nil or nil, "connection closed early"
    end
    sink(d)
    if left then left = left - #d end
  end
  return true
end

-- get(url, sink, connect) -> status, err. connect(scheme, host, port) -> conn | nil, err
function M.get(url, sink, connect, redirects)
  redirects = redirects or 0
  local scheme, host, port, path = parse_url(url)
  if not scheme then return 400, "bad URL: " .. url end
  local conn, err = connect(scheme, host, port)
  if not conn then return 502, err end
  local ok, serr = conn:send(("GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: vpm\r\nAccept: */*\r\nConnection: close\r\n\r\n")
    :format(path, host))
  if not ok then conn:close(); return 502, serr end
  local r = reader(conn)
  local status_line, lerr = r.line()
  local status = status_line and tonumber(status_line:match("^HTTP/%d%.%d (%d%d%d)"))
  if not status then conn:close(); return 502, lerr or ("bad response: " .. tostring(status_line)) end
  local headers = {}
  while true do
    local l, herr = r.line()
    if not l then conn:close(); return 502, herr end
    if l == "" then break end
    local k, v = l:match("^([^:]+):%s*(.*)$")
    if k then headers[k:lower()] = v end
  end
  if status >= 300 and status < 400 and headers.location then
    conn:close()
    if redirects >= MAX_REDIRECTS then return 502, "too many redirects" end
    local loc = headers.location
    if loc:sub(1, 1) == "/" then loc = ("%s://%s:%d%s"):format(scheme, host, port, loc)
    elseif not loc:match("^https?://") then return 502, "unsupported redirect: " .. loc end
    return M.get(loc, sink, connect, redirects + 1)
  end
  if status ~= 200 then conn:close(); return status, status_line end
  local done, berr = body(r, headers, sink)
  conn:close()
  if not done then return 502, berr end
  return 200
end

-- connect function over vsock / vtls. M.cafile (the config's `cafile`) is the PEM bundle https servers are verified
-- against; there is no way to skip verification.
-- on vlr (vapor.net) a plain connection comes from there, wrapped into the { send, recv(max, timeout), close } shape vsock has
local function vapor_connect(host, port)
  local ok, net = pcall(require, "vapor.net")
  if not ok then return nil end
  local s, err = net.connect(host, port)
  if not s then return nil, err or "connect failed" end
  return {
    send = function(_, data) local w, e = s:write(data); if w then return true end return nil, e end,
    recv = function(_, max, timeout)
      s:settimeout(timeout)
      local d, e = s:readsome(max)
      if d then return d end
      if e == "eof" then return "" end -- vsock: "" at end of stream
      return nil, e
    end,
    close = function() s:close() end,
  }
end

function M.vsock_connect(scheme, host, port)
  if scheme == "http" and not package.loaded["vsock"] then
    local c, err = vapor_connect(host, port)
    if c or err then return c, err end
  end
  if scheme == "https" then
    if not M.cafile then return nil, "https needs `cafile` (a PEM bundle of trusted roots) in the vpm config" end
    local ok, vtls = pcall(require, "vtls")
    if not ok then return nil, "this build has no TLS (vtls)" end
    return vtls.connect(host, port, M.cafile)
  end
  return require("vsock").connect(host, port)
end

return M
