return {
  name       = "me-monitor",
  version    = "1.0.0",
  rel        = 1,
  desc       = "Applied Energistics 2: power, items, crafting CPUs and low-stock alerts",
  depends    = { "byteos>=1.16.0" },
  optdepends = { "libnotify: alerts as notifications (with dunst)" },
  backup     = { "/etc/me-monitor.conf" },
  install    = "me-monitor.install",
}
