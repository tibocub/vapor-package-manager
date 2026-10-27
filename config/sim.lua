-- /etc/vpm.lua on the NuttX simulator (the global library directory is the hostfs mount, see vaporOS docs/lua-runtime.md).
return {
  libdir  = "/usr/lib/lua",
  appdir  = "/usr/apps",
  bindir  = "/usr/bin",
  index   = "file:///usr/mirror/index/v1",
  reserve = 0,
  profile = "full",
}
