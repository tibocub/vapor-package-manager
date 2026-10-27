-- Runs ON the board after tools/deploy-board.sh has uploaded the flat files d--<path with -- for />:
-- creates the directories and moves each file to /flash/<path>. Lives in /flash only during deployment.
local lfs = require("lfs")
local n = 0
local names = {}
for f in lfs.dir("/flash") do if f:sub(1, 3) == "d--" then names[#names + 1] = f end end
for _, f in ipairs(names) do
  local dest = "/flash/" .. f:sub(4):gsub("%-%-", "/")
  local dir = ""
  for part in dest:match("^(.*)/[^/]*$"):gmatch("[^/]+") do
    dir = dir .. "/" .. part
    if not lfs.attributes(dir, "mode") then assert(lfs.mkdir(dir)) end
  end
  os.remove(dest)
  assert(os.rename("/flash/" .. f, dest))
  n = n + 1
end
print("UNPACKED " .. n .. " files")
