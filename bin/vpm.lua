#!/usr/bin/env lua
-- Host entry point: lua bin/vpm.lua <command>. On a device the launcher vpm installs for itself does the same
-- with the library directory on package.path.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/../lib/?.lua;" .. package.path
os.exit(require("vpm.cli").main({ table.unpack(arg) }, {}))
