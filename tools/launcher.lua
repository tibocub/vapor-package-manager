#!/bin/lua
os.exit(require("vpm.cli").main({ table.unpack(arg) }, {}))
