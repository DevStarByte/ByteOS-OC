return {
  name    = "netfs",
  version = "1.0.0",
  rel     = 1,
  desc    = "shared folders: use another computer's directories over the network",
  depends = { "byteos>=1.12.1" },
  backup  = { "/etc/netfs.conf" },
  install = "netfs.install",
}
