-- vpm search [words] [--pure | --native=none|c|any] [--host=a,b | --no-host] [--works] [--all]
-- Everything in the index is listed; the flags only narrow it. Each line carries what it takes to use the package:
--   pure | c | build | other   (what building needs, see docs/native-detection.md)   host:nvim ...   vlr:ok (loads and runs on vlr in our tests)
local MAX = 40

return function(ctx, args)
  local f = ctx.flags
  local native = f.pure and "none" or f.native or "any"
  if native ~= "none" and native ~= "c" and native ~= "any" then ctx.err("--native must be none, c or any"); return 2 end
  local hosts
  if f.host then hosts = {}; for h in f.host:gmatch("[^,]+") do hosts[h] = true end end

  local list, status, err = ctx.index():catalogue()
  if not list then ctx.err("%s", err or ("index error " .. tostring(status))); return 4 end

  local words = {}
  for _, w in ipairs(args) do words[#words + 1] = w:lower() end
  local found = {}
  for _, e in ipairs(list) do
    local c = e.c or "pure"
    local ok = true
    if native == "none" and c ~= "pure" then ok = false end
    if native == "c" and c ~= "pure" and c ~= "c" then ok = false end
    if hosts and not hosts[e.h or ""] then ok = false end
    if f.no_host and e.h then ok = false end
    if f.works and e.w ~= "ok" then ok = false end
    if ok then
      local hay = (e.n .. " " .. (e.s or "")):lower()
      for _, w in ipairs(words) do if not hay:find(w, 1, true) then ok = false; break end end
    end
    if ok then found[#found + 1] = e end
  end
  table.sort(found, function(a, b)
    local an, bn = a.n:lower(), b.n:lower()
    for _, w in ipairs(words) do   -- an exact name first, then names that contain a word, then the rest
      if an == w and bn ~= w then return true elseif bn == w and an ~= w then return false end
    end
    return an < bn
  end)

  local shown = f.all and #found or math.min(#found, MAX)
  for i = 1, shown do
    local e = found[i]
    local tags = { e.c or "pure" }
    if e.h then tags[#tags + 1] = "host:" .. e.h end
    if e.w == "ok" then tags[#tags + 1] = "vlr:ok" elseif e.w == "fail" then tags[#tags + 1] = "vlr:fails" end
    ctx.out("%s %s  [%s]%s", e.n, e.v or "", table.concat(tags, " "), e.s and ("  " .. e.s) or "")
  end
  if #found == 0 then ctx.out("nothing found") return 1 end
  if shown < #found then ctx.out("... %d more (narrow the search, or --all)", #found - shown) end
  return 0
end
