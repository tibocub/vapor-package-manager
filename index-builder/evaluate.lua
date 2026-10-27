-- Rockspec-level stage shared by run.lua and build.lua: evaluate every downloaded rockspec and apply filter.check.
-- evaluate(manifest, dir) -> names (sorted), checked (name -> {ok=,reason=,deps=,version=,host=,rs=}), stats
local manifest, sandbox, filter = require("manifest"), require("sandbox"), require("filter")

return function(repo, dir)
  local names = {}
  for name in pairs(repo) do names[#names + 1] = name end
  table.sort(names)
  local checked, stats = {}, { missing = 0, eval = 0 }
  for _, name in ipairs(names) do
    local ver = manifest.latest(repo[name])
    local f = io.open(("%s/%s-%s.rockspec"):format(dir, name, ver), "rb")
    if not f then
      stats.missing = stats.missing + 1
    else
      local text = f:read("a"); f:close()
      local rs = sandbox.load(text, name)
      if not rs then
        stats.eval = stats.eval + 1
        checked[name] = { ok = false, reason = "rockspec-error", version = ver }
      else
        local ok, reason, info = filter.check(rs)
        checked[name] = ok and { ok = true, deps = info.deps, version = ver, host = info.host, rs = rs }
                            or { ok = false, reason = reason, version = ver }
      end
    end
  end
  return names, checked, stats
end
