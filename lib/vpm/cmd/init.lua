-- vpm init [-y] : write a vpm.lua for the current directory.
local fs = require("vpm.fs")

return function(ctx)
  local path = ctx.cwd .. "/vpm.lua"
  if fs.exists(path) then ctx.err("vpm.lua already exists here"); return 1 end
  local name = ctx.cwd:match("([^/]+)/*$") or "project"
  local kind, entry = "lib", "main.lua"
  if not ctx.flags.yes then
    local read = ctx.env.read or io.read
    ctx.env.out = ctx.env.out or io.write
    local function ask(q, default)
      (ctx.env.out)(("%s [%s]: "):format(q, default))
      local l = read()
      return (l and l ~= "") and l or default
    end
    name = ask("name", name)
    kind = ask("kind (lib/app)", kind)
    if kind == "app" then entry = ask("entry file", entry) end
  end
  if kind ~= "lib" and kind ~= "app" then ctx.err("kind must be lib or app"); return 2 end
  local lines = { "return {", ('  name = %q, version = "0.1.0",'):format(name) }
  if kind == "app" then
    lines[#lines + 1] = ('  kind = "app", bin = { [%q] = %q },'):format(name, entry)
  end
  lines[#lines + 1] = "  deps = {},"
  lines[#lines + 1] = "}"
  local ok, err = fs.write(path, table.concat(lines, "\n") .. "\n")
  if not ok then ctx.err("%s", err); return 1 end
  ctx.out("wrote vpm.lua")
  return 0
end
