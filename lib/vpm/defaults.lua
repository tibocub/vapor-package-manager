-- What vpm uses when there is no configuration file (a desktop with nothing set up): the public index on GitHub Pages and a per-user install.
-- Boards and the simulator always have a vpm.lua generated at firmware build time, which wins over all of this.
local M = {}

M.index = "https://tibocub.github.io/vpm-index/index/v1"
M.keys = { "6b0c70b6b75f606a4a8deb2e19d31d8be9028bd4e6449a65c6d66c5b0c4ff2ca" }

-- nil when there is no home directory to put files in
function M.config(home)
  if not home or home == "" then return nil end
  return { libdir = home .. "/.local/share/vpm/lib", appdir = home .. "/.local/share/vpm/apps", bindir = home .. "/.local/bin", index = M.index, keys = M.keys, reserve = 0, profile = "full" }
end

return M
