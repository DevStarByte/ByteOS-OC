return {
  name    = "timers",
  version = "1.0.1",
  rel     = 1,
  desc    = "start services on a schedule (systemd-style .timer units)",
  depends = { "byteos>=1.12.1" },
  install = "timers.install",
}
