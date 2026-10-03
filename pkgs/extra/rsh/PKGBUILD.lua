return {
  name    = "rsh",
  version = "1.0.0",
  rel     = 1,
  desc    = "remote shell: run commands on another ByteOS computer",
  depends = { "byteos>=1.12.1" },
  install = "rsh.install",
}
