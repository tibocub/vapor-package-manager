package.path = "lib/?.lua;" .. package.path
local http = require("vpm.http")

-- a fake connection that answers each request with the next canned response, in pieces of `step` bytes
local function fake(responses, step, log)
  return function(scheme, host, port)
    local resp = table.remove(responses, 1)
    local pos = 0
    return {
      send = function(_, d) log[#log + 1] = { host = host, port = port, req = d } return true end,
      recv = function(_, max) local s = resp:sub(pos + 1, pos + math.min(max, step)); pos = pos + #s; return s end,
      close = function() end,
    }
  end
end

local function get(url, responses, step)
  local out, log = {}, {}
  local status, err = http.get(url, function(c) out[#out + 1] = c end, fake(responses, step or 7, log))
  return status, err, table.concat(out), log
end

local s, e, b, log = get("http://h.example:8080/a/b?x=1", { "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX: y\r\n\r\nhello" })
assert(s == 200 and b == "hello", tostring(s) .. tostring(e))
assert(log[1].host == "h.example" and log[1].port == 8080 and log[1].req:match("^GET /a/b%?x=1 HTTP/1.1\r\nHost: h.example\r\n"))

s, e, b = get("http://h/", { "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n" })
assert(s == 200 and b == "Wikipedia", tostring(e))

s, e, b = get("http://h/", { "HTTP/1.0 200 OK\r\n\r\nuntil close" })
assert(s == 200 and b == "until close")

s, e, b, log = get("http://h/old", { "HTTP/1.1 301 Moved\r\nLocation: /new\r\n\r\n", "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok" })
assert(s == 200 and b == "ok" and log[2].req:match("^GET /new "), "relative redirect")

s, e, b, log = get("http://a/x", { "HTTP/1.1 302 Found\r\nLocation: http://other:81/y\r\n\r\n", "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nz" })
assert(s == 200 and log[2].host == "other" and log[2].port == 81, "absolute redirect")

s = get("http://h/", { "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n" })
assert(s == 404)

s, e = get("http://h/", { "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nshort" })
assert(s == 502 and e:match("closed"), "truncated body must fail: " .. tostring(e))

local loop = {}
for i = 1, 8 do loop[i] = "HTTP/1.1 301 M\r\nLocation: /n\r\n\r\n" end
s, e = get("http://h/", loop)
assert(s == 502 and e:match("redirects"))

s, e = http.get("https://h/", function() end, http.vsock_connect)
assert(s == 502 and e:match("cafile"), e)

print("http ok")
