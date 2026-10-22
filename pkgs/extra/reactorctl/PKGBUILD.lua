return {
  name    = "reactorctl",
  version = "1.0.0",
  rel     = 1,
  desc    = "Big/Extreme Reactors: status, control and automatic control rods by the energy buffer",
  depends = { "byteos>=1.16.0" },
  backup  = { "/etc/reactorctl.conf" },
  install = "reactorctl.install",
}
