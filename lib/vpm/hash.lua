-- Incremental SHA-256. Pure Lua fallback (needs 64-bit integers, which vaporOS keeps on purpose); about 7 KB/s on
-- the RP2040, so the firmware should provide vapor.sha256 (docs/vaporos-prerequisites.md P3) and this module will
-- use it as soon as it exists: the same interface, a C implementation behind it.
local M = {}

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2 }
local MASK = 0xffffffff
local function rotr(x, n) return ((x >> n) | (x << (32 - n))) & MASK end

local function compress(h, s, pos)
  local w = {}
  for i = 0, 15 do w[i] = string.unpack(">I4", s, pos + i * 4) end
  for i = 16, 63 do
    local a, b = w[i - 15], w[i - 2]
    w[i] = (w[i - 16] + (rotr(a, 7) ~ rotr(a, 18) ~ (a >> 3)) + w[i - 7] + (rotr(b, 17) ~ rotr(b, 19) ~ (b >> 10))) & MASK
  end
  local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
  for i = 0, 63 do
    local t1 = (hh + (rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)) + ((e & f) ~ (~e & g)) + K[i + 1] + w[i]) & MASK
    local t2 = ((rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)) + ((a & b) ~ (a & c) ~ (b & c))) & MASK
    hh, g, f, e, d, c, b, a = g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
  end
  h[1] = (h[1] + a) & MASK; h[2] = (h[2] + b) & MASK; h[3] = (h[3] + c) & MASK; h[4] = (h[4] + d) & MASK
  h[5] = (h[5] + e) & MASK; h[6] = (h[6] + f) & MASK; h[7] = (h[7] + g) & MASK; h[8] = (h[8] + hh) & MASK
end

local H = {}
H.__index = H

function M.new()
  return setmetatable({ h = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 },
                        buf = "", len = 0 }, H)
end

function H:update(chunk)
  self.len = self.len + #chunk
  local s, pos = self.buf .. chunk, 1
  while #s - pos + 1 >= 64 do compress(self.h, s, pos); pos = pos + 64 end
  self.buf = s:sub(pos)
  return self
end

function H:hex()
  local s = self.buf .. "\128" .. ("\0"):rep((55 - self.len) % 64) .. string.pack(">I8", self.len * 8)
  local h = { table.unpack(self.h) }
  for pos = 1, #s, 64 do compress(h, s, pos) end
  return (("%08x"):rep(8)):format(table.unpack(h))
end

function M.hex(s) return M.new():update(s):hex() end

return M
