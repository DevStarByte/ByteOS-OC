return {
  name    = "hypridle",
  version = "1.0.0",
  rel     = 1,
  desc    = "run commands after a while without input in Hyprbyte, e.g. lock the screen",
  depends = { "hyprbyte>=1.2.0" },
  backup  = { "/etc/hypr/hypridle.conf" },
}
