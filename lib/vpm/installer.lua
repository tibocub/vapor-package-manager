-- Applies a resolver plan: download into staging, verify, move into place, write records last
-- (docs/state-and-tracking.md "Safety and crashes"), and the reverse for remove.
-- Exit-code-like second results: "usage" problems are nil,msg; 3 conflict; 4 network/integrity (nothing changed).
local fs = require("vpm.fs")
local hashmod = require("vpm.hash")
local Maintain = require("vpm.maintain")
local M = {}
local I = setmetatable({}, { __index = Maintain.class })      -- remove / check / repair / state come from maintain.lua
I.__index = I

-- cfg = { libdir, appdir, bindir, local_root, reserve?, free_space? }
function M.new(o)
  return setmetatable({ cfg = o.cfg, transport = o.transport, index = o.index,
                        now = o.now or os.time, states = {} }, I)
end

-- Index data is remote: nothing in it may name a path outside its package directory.
local function safe_rel(p)
  if type(p) ~= "string" or p == "" or p:sub(1, 1) == "/" or p:find("\\", 1, true) or p:find("%z") then return false end
  for part in p:gmatch("[^/]+") do if part == ".." or part == "." then return false end end
  return true
end
local function safe_name(n) return type(n) == "string" and n:match("^[%w][%w%._%-]*$") ~= nil end

local function split_dep(s) local n, c = s:match("^(%S+)%s*(.*)$"); return n, c end

local function launcher(appdir, name, entry)
  local dir = appdir .. "/" .. name
  return ("#!/bin/lua\npackage.path = %q .. package.path\narg[0] = %q; return dofile(arg[0])\n")
    :format(dir .. "/lua_modules/?.lua;" .. dir .. "/?.lua;", dir .. "/" .. entry)
end

-- plan: from the resolver. requested: name -> constraint text the user typed (these join the world set)
function I:apply(plan, requested)
  requested = requested or {}
  local scopes, jobs, own_cache, made, locked, created = {}, {}, {}, {}, {}, {}
  local function undo_created()
    for i = #created, 1, -1 do
      local c = created[i]
      if not c.job.done then          -- completed packages keep their files: they have a record
        fs.remove(c.path)
        fs.prune(c.path:match("^(.*)/[^/]*$"), c.stop)
      end
    end
    created = {}
  end
  local function fail(code, msg)
    undo_created()
    for scope, st in pairs(scopes) do
      st:clear_staging()
      if locked[scope] then st:unlock() end
    end
    return nil, msg, code
  end

  for _, a in ipairs(plan.actions) do
    if a.scope ~= "firmware" and not scopes[a.scope] then
      local st, err = self:state(a.scope)
      if not st then return nil, err, 1 end
      scopes[a.scope] = st
    end
  end

  -- 1. validate everything before touching the disk
  local total = 0
  for _, a in ipairs(plan.actions) do
    if a.action == "install" then
      local doc, err = self.index:package(a.name)
      local meta = doc and doc.versions[a.version]
      if not meta then return fail(4, err or ("index has no " .. a.name .. " " .. a.version)) end
      if not safe_name(a.name) then return fail(1, "unsafe package name: " .. tostring(a.name)) end
      local st = scopes[a.scope]
      local kind = doc.kind == "app" and "app" or "lib"
      local base = self:base_dir(st, kind, a.name)
      own_cache[a.scope] = own_cache[a.scope] or self.owners(st)
      local own = kind == "lib" and own_cache[a.scope] or {}
      local old = st:get(a.name)
      local job = { a = a, st = st, kind = kind, base = base, files = {}, meta = meta, old = old }
      local any_existing = false
      for dest, f in pairs(meta.files or {}) do
        if not safe_rel(dest) then return fail(1, ("%s: unsafe file path '%s' in index"):format(a.name, dest)) end
        local target = base .. "/" .. dest
        local existed = fs.exists(target)
        if existed then
          any_existing = true
          if not old and own[dest] ~= a.name then
            return fail(1, ("%s: %s exists and is %s (not overwritten)"):format(a.name, target,
              own[dest] and ("owned by " .. own[dest]) or "not managed by vpm"))
          end
        end
        job.files[#job.files + 1] = { dest = dest, url = f.url, sha256 = f.sha256, size = f.size, existed = existed }
        total = total + (f.size or 0)
      end
      for cmd, entry in pairs(type(meta.bin) == "table" and meta.bin or {}) do
        if not safe_name(cmd) or not safe_rel(entry) then return fail(1, a.name .. ": unsafe bin entry in index") end
      end
      -- A fresh install is written straight to its final place and undone by the journal if anything fails;
      -- an upgrade goes through staging so the working version survives a failed download.
      job.direct = not old and not any_existing
      table.sort(job.files, function(x, y) return x.dest < y.dest end)
      jobs[#jobs + 1] = job
    end
  end
  if self.cfg.free_space and self.cfg.reserve then
    local free = self.cfg.free_space()
    if free and free - total < self.cfg.reserve then
      return fail(4, ("not enough flash: need %d bytes, %d free, %d must stay free"):format(total, free, self.cfg.reserve))
    end
  end

  -- 1b. lock each scope; the lock file carries the journal of files created in place
  local journal = {}
  for _, j in ipairs(jobs) do
    if j.direct then
      local lines = journal[j.a.scope] or {}
      for _, f in ipairs(j.files) do lines[#lines + 1] = j.a.name .. "\t" .. j.base .. "/" .. f.dest end
      for cmd in pairs(type(j.meta.bin) == "table" and j.meta.bin or {}) do
        lines[#lines + 1] = j.a.name .. "\t" .. self.cfg.bindir .. "/" .. cmd
      end
      journal[j.a.scope] = lines
    end
  end
  for scope, st in pairs(scopes) do
    local ok, lerr = st:lock(journal[scope] and (table.concat(journal[scope], "\n") .. "\n") or nil)
    if not ok then return fail(1, lerr) end
    locked[scope] = true
  end

  -- 2. download and verify; staged jobs into staging, direct jobs straight to their place
  for _, j in ipairs(jobs) do
    for _, f in ipairs(j.files) do
      if not f.url then return fail(4, ("%s: no download URL for %s"):format(j.a.name, f.dest)) end
      local path = (j.direct and j.base or j.st:staging(j.a.name)) .. "/" .. f.dest
      local dir = path:match("^(.*)/[^/]*$")
      if not made[dir] then
        local ok, merr = fs.mkdirp(dir)
        if not ok then return fail(1, merr) end
        made[dir] = true
      end
      if j.direct then created[#created + 1] = { path = path, job = j, stop = j.kind == "app" and self.cfg.appdir or j.st.root } end
      local out, oerr = io.open(path, "wb")
      if not out then return fail(1, oerr) end
      local h, n = hashmod.new(), 0
      local status, err = self.transport.get(f.url, function(c) out:write(c); h:update(c); n = n + #c end)
      out:close()
      if status ~= 200 then return fail(4, ("download of %s failed: %s"):format(f.url, err or status)) end
      if f.size and n ~= f.size then return fail(4, ("%s %s: size %d, expected %d"):format(j.a.name, f.dest, n, f.size)) end
      if h:hex() ~= f.sha256 then return fail(4, ("%s %s: sha256 mismatch"):format(j.a.name, f.dest)) end
    end
  end

  -- 3. commit: replace old versions, move staged files, write the record last
  local when = os.date("%Y-%m-%d", self.now())
  local versions = {}
  for _, a in ipairs(plan.actions) do versions[a.name] = a.version end
  for _, j in ipairs(jobs) do
    local st, a, old = j.st, j.a, j.old
    if old then self:remove_files(st, old); made = {} end
    if not j.direct then
      for _, f in ipairs(j.files) do
        local target = j.base .. "/" .. f.dest
        local tdir = target:match("^(.*)/[^/]*$")
        local ok, err = true, nil
        if not made[tdir] then ok, err = fs.mkdirp(tdir); made[tdir] = ok end
        if ok then
          if f.existed and fs.exists(target) then fs.remove(target) end
          ok, err = fs.rename(st:staging(a.name) .. "/" .. f.dest, target)
        end
        if not ok then return fail(1, ("cannot place %s: %s (run 'vpm check')"):format(target, tostring(err))) end
      end
    end
    local rec = { name = a.name, version = a.version, kind = j.kind, base = j.kind, scope = a.scope,
                  reason = requested[a.name] and "world" or ((old and old.reason) or "dep"),
                  files = {}, deps = {}, resolved = {}, installed = when }
    for _, f in ipairs(j.files) do rec.files[f.dest] = f.sha256 end
    for _, d in ipairs(j.meta.deps or {}) do
      local n, c = split_dep(d)
      if n ~= "lua" then rec.deps[n] = c; rec.resolved[n] = versions[n] end
    end
    local bin = type(j.meta.bin) == "table" and j.meta.bin or {}
    if next(bin) then
      rec.bin, rec.launchers = bin, {}
      fs.mkdirp(self.cfg.bindir)
      for cmd, entry in pairs(bin) do
        local p = self.cfg.bindir .. "/" .. cmd
        fs.write(p, launcher(self.cfg.appdir, a.name, entry))
        rec.launchers[cmd] = p
      end
    end
    local ok, err = st:put(rec, not old)
    if not ok then return fail(1, "cannot write record: " .. tostring(err)) end
    j.done = true     -- this package is complete: the journal no longer applies to it
  end

  -- 4. world set; reused packages the user named are promoted from dependency to world
  for scope, st in pairs(scopes) do
    local world = st:world()
    for name, c in pairs(requested) do
      local rec = st:get(name)
      if rec then
        world[name] = c
        if rec.reason ~= "world" then rec.reason = "world"; st:put(rec) end
      end
    end
    st:set_world(world)
    st:clear_staging()
    st:unlock()
  end
  return true
end

return M
