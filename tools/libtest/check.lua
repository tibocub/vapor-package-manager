-- Runs INSIDE the sandbox (see driver.lua): vlr [--dialect=5.4] check.lua LIBDIR APPDIR MODULE
-- Loads one module of an installed library and prints "OK" or "ERR<TAB>first line of the error".
local libdir, appdir, mod = arg[1], arg[2], arg[3]
package.path = libdir .. "/?.lua;" .. libdir .. "/?/init.lua;" .. appdir .. "/?.lua;" .. appdir .. "/?/init.lua;" .. package.path
local ok, err = pcall(require, mod)
if ok then print("OK") else print("ERR\t" .. tostring(err):gsub("\n.*", "")) end
os.exit(0)
