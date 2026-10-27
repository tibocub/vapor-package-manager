package.path = "lib/?.lua;index-builder/?.lua;" .. package.path
local source = require("source")
local function raw(o, p) return source.raw_url(o, p) end
local git = function(url) return { type = "git", url = url, commit = "abc123" } end
local arc = function(url) return { type = "archive", url = url } end

assert(raw(git("https://github.com/o/r.git"), "src/a.lua") == "https://raw.githubusercontent.com/o/r/abc123/src/a.lua")
assert(raw(git("https://github.com/o/r"), "a.lua") == "https://raw.githubusercontent.com/o/r/abc123/a.lua")
assert(raw(git("https://gitlab.com/g/sub/r.git"), "a.lua") == "https://gitlab.com/g/sub/r/-/raw/abc123/a.lua")
assert(raw(git("https://framagit.org/o/r.git"), "a.lua") == "https://framagit.org/o/r/-/raw/abc123/a.lua")
assert(raw(git("https://codeberg.org/o/r.git"), "a.lua") == "https://codeberg.org/o/r/raw/commit/abc123/a.lua")
assert(raw(git("https://git.sr.ht/~o/r"), "a.lua") == "https://git.sr.ht/~o/r/blob/abc123/a.lua")
assert(raw(git("https://example.org/o/r.git"), "a.lua") == nil)                       -- unknown host: no URL, never a guess
assert(raw(arc("https://github.com/o/r/archive/v1.0.tar.gz"), "a.lua") == "https://raw.githubusercontent.com/o/r/v1.0/a.lua")
assert(raw(arc("https://github.com/o/r/archive/refs/tags/v1.0.zip"), "a.lua") == "https://raw.githubusercontent.com/o/r/v1.0/a.lua")
assert(raw(arc("https://github.com/o/r/tarball/v1.0"), "a.lua") == "https://raw.githubusercontent.com/o/r/v1.0/a.lua")
assert(raw(arc("https://github.com/o/r/releases/download/v1/x.tar.gz"), "a.lua") == nil)   -- release assets are not repository files
assert(raw(arc("https://dkolf.de/dkjson.tar.gz"), "a.lua") == nil)
assert(raw({ type = "git", url = "https://github.com/o/r" }, "a.lua") == nil)           -- no commit recorded
print("source ok")
