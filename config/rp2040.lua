-- /flash/etc/vpm.lua on the RP2040-Zero. bindir is a directory already on the shell's default PATH
-- (/flash/sb:/bin) once PATH is set (it is unset by default, see docs/vaporos-prerequisites.md P2).
return {
  libdir  = "/flash/lib/lua",
  appdir  = "/flash/apps",
  bindir  = "/flash/sb",
  index   = "file:///flash/mirror/index/v1",     -- an SD card or a copied mirror until the board has networking
  reserve = 64 * 1024,
  profile = "small",
}
