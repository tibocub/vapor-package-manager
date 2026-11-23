-- vpm bundle PKG... [--dir=DIR] : compile C rocks INTO a vlr instead of installing .so files.
-- Fetches each rock's source rock (size and sha256 checked against the signed index), unpacks it under DIR/src and writes DIR/bundle.conf: one modules.conf line per
-- C module of the plan (name, luaopen_ symbol, sources, -D/-I flags). Then, in the vlr checkout:  make CONF_EXTRA=DIR/bundle.conf
-- Only the C modules are bundled; the Lua files of a rock keep coming from `vpm i` (or ./lua_modules).
local native = require("vpm.native")
local fs = require("vpm.fs")
local version = require("vpm.version")

return function(ctx, args)
  if #args == 0 then ctx.err("bundle which packages?"); return 2 end
  local dir = ctx.flags.dir or "vlr-bundle"
  if dir:sub(1, 1) ~= "/" then dir = ctx.cwd .. "/" .. dir end
  if dir:find("%s") or dir:find("%c") then ctx.err("--dir must not contain spaces"); return 2 end
  local prof = ctx.profile()
  local lines, seen = {}, {}
  for _, name in ipairs(args) do
    if not seen[name] then
      seen[name] = true
      local doc, err = ctx.index():package(name)
      if not doc then ctx.err("%s", err or (name .. " is not in the index")); return err and 4 or 1 end
      local vs = {}
      for v in pairs(doc.versions) do vs[#vs + 1] = v end
      table.sort(vs, function(a, b) return version.less(b, a) end)
      local ver = vs[1]
      local m = doc.versions[ver]
      if not native.buildable(m) then
        ctx.err("%s %s cannot be bundled: %s", name, ver, m.native and (m.native.no_plan_reason or ("native class " .. tostring(m.native.native))) or "it is pure Lua (nothing to compile; vpm i it)")
        return 4
      end
      if m.native.plan.make or m.native.plan.cmake then ctx.err("%s cannot be bundled: it is built by its own %s scripts, not compiled from a source list", name, m.native.plan.make and "make" or "cmake"); return 4 end
      local ok, verr = native.validate(m.native.plan)
      if not ok then ctx.err("%s: %s", name, verr); return 4 end
      for _, mod in ipairs(m.native.plan.modules) do
        for _, l in ipairs(mod.libraries or {}) do
          if l ~= "m" and l ~= "dl" and l ~= "pthread" then   -- already linked into vlr; any other library would have to be linked in by hand
            ctx.err("%s needs the system library %s: bundling that is not supported yet", name, l); return 4
          end
        end
      end
      local base = ("%s/src/%s-%s"):format(dir, name, ver)
      fs.mkdirp(base)
      local rock = base .. "/source.rock"
      local src = m.luarocks.src
      local status, derr, n, hex = ctx.installer():download(src.url, rock)
      if status ~= 200 then ctx.err("download of %s failed: %s", src.url, derr or status); return 4 end
      if (src.size and n ~= src.size) or hex ~= src.sha256 then ctx.err("%s: source rock does not match the index (size or sha256)", name); return 4 end
      local root, uerr = native.unpack(prof, rock, base, m.native.srcdir)
      if not root then ctx.err("%s: %s", name, uerr); return 1 end
      if root:find("%s") then ctx.err("%s: source path contains spaces", name); return 1 end
      for _, mod in ipairs(m.native.plan.modules) do
        local t = { mod.name, "luaopen_" .. mod.name:gsub("%.", "_") }
        for _, s in ipairs(mod.sources) do t[#t + 1] = root .. "/" .. s end
        for _, d in ipairs(mod.defines or {}) do t[#t + 1] = "-D" .. d end
        for _, d in ipairs(mod.incdirs or {}) do t[#t + 1] = "-I" .. (d:sub(1, 1) == "/" and d or (root .. "/" .. d)) end
        lines[#lines + 1] = table.concat(t, " ")
      end
      ctx.out("  %s %s: %d module(s)", name, ver, #m.native.plan.modules)
    end
  end
  local f, ferr = io.open(dir .. "/bundle.conf", "wb")
  if not f then ctx.err("cannot write %s/bundle.conf: %s", dir, tostring(ferr)); return 1 end
  f:write("# written by vpm bundle: C modules compiled into the runtime (sources hash-checked against the signed index)\n", table.concat(lines, "\n"), "\n")
  f:close()
  ctx.out("wrote %s/bundle.conf; in the vlr checkout: make CONF_EXTRA=%s/bundle.conf", dir, dir)
  return 0
end
