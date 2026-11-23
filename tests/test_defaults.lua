package.path = "lib/?.lua;" .. package.path
local d = require("vpm.defaults")
assert(d.config(nil) == nil and d.config("") == nil)
local c = d.config("/home/u")
assert(c.libdir == "/home/u/.local/share/vpm/lib" and c.bindir == "/home/u/.local/bin" and c.index:match("^https://") and #c.keys == 1 and #c.keys[1] == 64)
print("defaults ok")
