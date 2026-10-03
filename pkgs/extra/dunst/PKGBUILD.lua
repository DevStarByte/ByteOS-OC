return {
  name    = "dunst",
  version = "1.0.0",
  rel     = 1,
  desc    = "notification pop-ups for Hyprbyte, with history and do-not-disturb",
  depends = { "libnotify", "hyprbyte>=1.2.0" },
  backup  = { "/etc/dunst/dunstrc" },
  install = "dunst.install",
}
