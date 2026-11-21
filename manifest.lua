return {
  name = "vpm", version = "0.1.0", entry = "bin/vpm.lua",
  needs = {vlr = "0.2", caps = {"fs"}, modules = {"lfs", "cjson", "std.http", "vapor.tls", "vapor.sign"}},
}
