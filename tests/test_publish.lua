package.path = "lib/?.lua;index-builder/?.lua;tests/lib/?.lua;" .. package.path
local fs, cli, rockspec = require("vpm.fs"), require("vpm.cli"), require("vpm.rockspec")
local sandbox = require("sandbox")
local decode = require("json_decode")

-- the generator: output must load as a rockspec through the same sandbox the index builder uses, and say what the manifest says
assert(rockspec.module_name("a/b/init.lua") == "a.b" and rockspec.module_name("x.lua") == "x" and rockspec.module_name("a/c.lua") == "a.c")
local text, ver = rockspec.generate({ name = "tool", version = "0.2.0", description = 'A "quoted" tool', license = "MIT", deps = { penlight = "~> 1.13", lpeg = ">= 1.0" },
  kind = "app", bin = { tool = "main.lua" } }, { "main.lua", "tool.lua", "tool/init.lua", "tool/util.lua" }, { url = "git+https://example.org/u/tool.git", tag = "v0.2.0" })
assert(ver == "0.2.0-1")
local rs = assert(sandbox.load(text, "tool-0.2.0-1.rockspec"))
assert(rs.package == "tool" and rs.version == "0.2.0-1" and rs.source.tag == "v0.2.0" and rs.description.summary == 'A "quoted" tool' and rs.description.license == "MIT")
assert(rs.dependencies[1] == "lua >= 5.1" and rs.dependencies[2] == "lpeg >= 1.0" and rs.dependencies[3] == "penlight ~> 1.13")
assert(rs.build.type == "builtin" and rs.build.modules["tool"] == "tool/init.lua" or rs.build.modules["tool"] ~= nil)
assert(rs.build.modules["tool.util"] == "tool/util.lua" and rs.build.modules["main"] == nil and rs.build.install.bin.tool == "main.lua")
assert(select(2, rockspec.generate({ name = "x", version = "1.0-3" }, {}, { url = "u", tag = "t" })) == "1.0-3", "an explicit revision is kept")
assert(rockspec.source_url("git@github.com:u/r.git\n") == "git+https://github.com/u/r.git")
assert(rockspec.source_url("https://codeberg.org/u/r") == "git+https://codeberg.org/u/r")
assert(rockspec.source_url("ssh://git@host.org/u/r.git") == "git+https://host.org/u/r.git")
assert(not rockspec.source_url("/home/me/repo"))

-- the command, with git and luarocks.org replaced
local base = os.tmpname(); os.remove(base); assert(fs.mkdirp(base .. "/proj/lib"))
fs.write(base .. "/proj/vpm.lua", 'return { name = "pubdemo", version = "1.2.0", description = "demo", deps = { lpeg = ">= 1.0" } }\n')
fs.write(base .. "/proj/pubdemo.lua", "return 1\n")
fs.write(base .. "/proj/lib/helper.lua", "return 2\n")
local tags, remote_tags = { ["refs/tags/v1.2.0"] = true }, { ["refs/tags/v1.2.0"] = true }
local function git(a)
  if a:find("remote get-url", 1, true) then return "git@example.org:me/pubdemo.git\n", 0 end
  local t = a:match("rev%-parse %-q %-%-verify '(.-)'")
  if t then return "", tags[t] and 0 or 1 end
  t = a:match("ls%-remote %-%-exit%-code %-%-tags origin '(.-)'")
  if t then return "", remote_tags[t] and 0 or 2 end
  error("unexpected git " .. a)
end
local calls, reply = {}, {}
local function http(o) calls[#calls + 1] = o; local r = table.remove(reply, 1); if not r then return nil, "no reply" end return r end
local envvars = {}
local function run(args, answers)
  local out, err = {}, {}
  local code = cli.main(args, { config = { libdir = base .. "/l", appdir = base .. "/a", bindir = base .. "/b", index = "file://" .. base .. "/none" }, decode = decode, cwd = base .. "/proj",
    out = function(s) out[#out + 1] = s end, err = function(s) err[#err + 1] = s end, git = git, http = { request = http }, getenv = function(k) return envvars[k] end,
    read = function() return table.remove(answers or {}, 1) end, now = function() return 0 end })
  return code, table.concat(out), table.concat(err)
end
local function has(s, p) return s:find(p, 1, true) ~= nil end

local code, out = run({ "publish" })
assert(code == 0 and has(out, "pubdemo 1.2.0-1 from git+https://example.org/me/pubdemo.git at tag v1.2.0") and has(out, "dry run") and has(out, '["lib.helper"] = "lib/helper.lua"') and #calls == 0, out)
tags["refs/tags/v1.2.0"] = nil
code, out, err = run({ "publish" }); assert(code == 1 and has(err, "no git tag"), err)
tags["refs/tags/1.2.0"], remote_tags["refs/tags/v1.2.0"] = true, nil          -- the plain tag exists locally, nothing is pushed
code, out, err = run({ "publish" }); assert(code == 1 and has(err, "not on the remote"), err)
remote_tags["refs/tags/1.2.0"] = true
code, out = run({ "publish", "--revision=2" }); assert(code == 0 and has(out, "at tag 1.2.0") and has(out, "pubdemo 1.2.0-2"), out)

code, out, err = run({ "publish", "--upload" }); assert(code == 1 and has(err, "VPM_LUAROCKS_KEY") and #calls == 0, err)
envvars.VPM_LUAROCKS_KEY = "secret"
reply = { { status = 200, body = '{"module":null,"version":null}' } }
code, out = run({ "publish", "--upload" }, { "n" })
assert(code == 1 and has(out, "creates a new module") and has(out, "not uploaded") and #calls == 1, out)
assert(has(calls[1].url, "/api/1/bearer/check_rockspec?package=pubdemo&version=1.2.0-1") and calls[1].headers.Authorization == "Bearer secret")
calls = {}
reply = { { status = 200, body = '{"module":{"id":1},"version":{"id":2}}' } }
code, out, err = run({ "publish", "--upload", "-y" }); assert(code == 1 and has(err, "already on luarocks.org") and #calls == 1, err)
calls = {}
reply = { { status = 200, body = '{"module":{"id":1},"version":null}' }, { status = 200, body = '{"module_url":"https://luarocks.org/modules/me/pubdemo","is_new":false}' } }
code, out = run({ "publish", "--upload", "-y" })
assert(code == 0 and has(out, "published: https://luarocks.org/modules/me/pubdemo") and #calls == 2, out)
local up = calls[2]
assert(up.method == "POST" and up.url == "https://luarocks.org/api/1/bearer/upload" and up.headers.Authorization == "Bearer secret" and up.headers["Content-Type"]:find("^multipart/form%-data; boundary="))
assert(has(up.body, 'name="rockspec_file"; filename="pubdemo-1.2.0-1.rockspec"') and has(up.body, 'package = "pubdemo"'))
calls = {}
reply = { { status = 200, body = '{"module":null,"version":null}' }, { status = 400, body = '{"errors":["Rockspec has no valid source"]}' } }
code, out, err = run({ "publish", "--upload", "-y" }); assert(code == 4 and has(err, "Rockspec has no valid source"), err)
reply = { { status = 401, body = '{"errors":["Invalid key"]}' } }
code, out, err = run({ "publish", "--upload", "-y" }); assert(code == 4 and has(err, "refused the key"), err)

os.execute("rm -rf '" .. base .. "'")
print("publish ok")
